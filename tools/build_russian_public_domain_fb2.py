#!/usr/bin/env python3
"""Build TWO real, independent Russian public-domain FB2 test books.

The texts are fetched from Russian Wikisource pages for Afanasyev's
historical folk tales. Never fall back to invented prose or a stub.
The exact downloaded source, FB2 bytes and SHA-256 manifest remain in the
CI runner; source text is not copied into the public Git repository.

No AI request, private uploaded book or extra Python dependency is used.
"""
from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request
from xml.etree import ElementTree as ET

BASE = "https://ru.wikisource.org"
PAGE = "Народные русские сказки (Афанасьев)/"
NAMESPACE = "http://www.gribuser.ru/xml/fictionbook/2.0"
MAX_SOURCE_BYTES = 3 * 1024 * 1024
SOURCES = {
    "morozko": {
        "title": "Морозко",
        "page": PAGE + "Морозко",
        "sections": ("95", "96"),
        "standalone_variant": "95",
        "markers": ("старик", "старуха"),
        "min_cyrillic": 1500,
    },
    "frog_princess": {
        "title": "Царевна-лягушка",
        "page": PAGE + "Царевна-лягушка",
        "sections": ("267", "268", "269"),
        "standalone_variant": "269",
        "markers": ("иван", "лягуш"),
        "min_cyrillic": 3000,
    },
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch_source(page: str) -> tuple[str, bytes, str]:
    page_param = urllib.parse.quote(page, safe="")
    candidates = [
        BASE + "/w/api.php?" + urllib.parse.urlencode({
            "action": "parse", "page": page,
            "prop": "text", "format": "json", "formatversion": "2",
        }),
        BASE + "/w/index.php?title=" + page_param + "&action=render",
        BASE + "/wiki/" + page_param,
    ]
    failures = []
    for url in candidates:
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "AI-Story-RPG-source-QA/1.0 (https://github.com/shonentez-afk/AI-Story-RPG; public-domain tests)",
                "Accept": "application/json,text/html;q=0.9",
            })
            with urllib.request.urlopen(req, timeout=18) as response:
                raw = response.read(MAX_SOURCE_BYTES + 1)
            if not (1000 <= len(raw) <= MAX_SOURCE_BYTES):
                raise ValueError("Source outside strict size bounds")
            decoded = raw.decode("utf-8-sig")
            if "api.php" in url:
                data = json.loads(decoded)
                parsed = data.get("parse", {})
                html = parsed.get("text")
                if isinstance(html, dict):
                    html = html.get("*")
                if not isinstance(html, str) or not html:
                    raise ValueError("Missing MediaWiki article HTML")
            else:
                html = decoded
            if "mw-parser-output" not in html and "<p" not in html:
                raise ValueError("No rendered document paragraphs")
            return html, raw, url
        except Exception as error:
            # Do not log source content or raw HTTP responses.
            failures.append(type(error).__name__)
    raise RuntimeError("Cannot fetch authentic Wikisource page; "
                       "refusing synthetic fallback (" +
                       ",".join(failures) + ")")


class ArticleParagraphs(HTMLParser):
    """Collect exact rendered story paragraphs grouped by numeric variants.

    Paragraphs outside article content, editor footnotes, navigation,
    wikimedia widgets and bibliography sections are excluded.
    """

    BLOCKED = frozenset(("script", "style", "sup", "table", "nav",
                         "footer", "aside", "figure"))
    STOP_SECTIONS = frozenset(("примечания", "источники", "ссылки",
                               "литература", "комментарии"))

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._content_depth = 0
        self._depth = 0
        self._blocked = 0
        self._heading_tag = ""
        self._heading_chunks: list[str] = []
        self._paragraph_depth = 0
        self._paragraph_chunks: list[str] = []
        self._section = ""
        self._stopped = False
        self._all: list[tuple[str, str, bool]] = []
        self._found_article = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._depth += 1
        props = dict(attrs)
        if tag in self.BLOCKED:
            self._blocked += 1
        if "mw-parser-output" in (props.get("class") or "").split():
            self._content_depth = self._depth
            self._found_article = True
        if self._blocked:
            return
        if tag in ("h2", "h3", "h4"):
            self._heading_tag = tag
            self._heading_chunks = []
        if tag == "p":
            self._paragraph_depth = self._depth
            self._paragraph_chunks = []

    def handle_data(self, data: str) -> None:
        if self._blocked:
            return
        if self._heading_tag:
            self._heading_chunks.append(data)
        if self._paragraph_depth:
            self._paragraph_chunks.append(data)

    def handle_endtag(self, tag: str) -> None:
        if not self._blocked:
            if tag == self._heading_tag:
                heading = " ".join(" ".join(self._heading_chunks).split())
                if heading.casefold() in self.STOP_SECTIONS:
                    self._stopped = True
                else:
                    number = re.fullmatch(r"(?:№\s*)?(\d{1,3})", heading)
                    if number:
                        self._section = number.group(1)
                self._heading_tag = ""
                self._heading_chunks = []
            if tag == "p" and self._paragraph_depth:
                text = " ".join(" ".join(self._paragraph_chunks).split())
                if text and not self._stopped:
                    self._all.append((self._section, text,
                                      bool(self._content_depth)))
                self._paragraph_depth = 0
                self._paragraph_chunks = []
        if tag in self.BLOCKED and self._blocked:
            self._blocked -= 1
        if self._content_depth == self._depth:
            self._content_depth = 0
        self._depth = max(0, self._depth - 1)

    def chapters(self, required: tuple[str, ...]) -> list[tuple[str, list[str]]]:
        # A valid MediaWiki render has an article container. For fragment
        # responses from the API the article HTML is the entire response.
        paragraphs = [entry for entry in self._all
                      if entry[2] or not self._found_article]
        result: dict[str, list[str]] = {num: [] for num in required}
        for number, text, _ in paragraphs:
            if number in result:
                result[number].append(text)
        if any(len(result[num]) < 2 for num in required):
            raise ValueError("Original article is missing a complete "
                             "numbered variant; refuse a partial book")
        return [(number, result[number]) for number in required]


def extract_real_tale(html: str, key: str) -> list[tuple[str, list[str]]]:
    spec = SOURCES[key]
    parser = ArticleParagraphs()
    parser.feed(html)
    parts = parser.chapters(spec["sections"])
    prose = "\n\n".join(p for _, chapter in parts for p in chapter)
    cyrillic = len(re.findall(r"[А-Яа-яЁё]", prose))
    if cyrillic < spec["min_cyrillic"]:
        raise ValueError("Historical Russian story was truncated")
    lowered = prose.casefold()
    if any(word not in lowered for word in spec["markers"]):
        raise ValueError("Wrong tale: required original text markers absent")
    if len(prose) > 200000:
        raise ValueError("Unexpectedly large or mixed source")
    return parts


def build_fb2(key: str, parts: list[tuple[str, list[str]]],
              *, book_title: str | None = None) -> bytes:
    ns = lambda tag: "{" + NAMESPACE + "}" + tag
    ET.register_namespace("", NAMESPACE)
    book = ET.Element(ns("FictionBook"))
    title_info = ET.SubElement(ET.SubElement(
        book, ns("description")), ns("title-info"))
    ET.SubElement(title_info, ns("book-title")).text = (
        book_title or SOURCES[key]["title"])
    author = ET.SubElement(title_info, ns("author"))
    ET.SubElement(author, ns("first-name")).text = "Александр"
    ET.SubElement(author, ns("middle-name")).text = "Николаевич"
    ET.SubElement(author, ns("last-name")).text = "Афанасьев"
    ET.SubElement(title_info, ns("lang")).text = "ru"
    ET.SubElement(title_info, ns("annotation"))
    body = ET.SubElement(book, ns("body"))
    for number, paragraphs in parts:
        section = ET.SubElement(body, ns("section"))
        heading = ET.SubElement(section, ns("title"))
        ET.SubElement(heading, ns("p")).text = (
            SOURCES[key]["title"] + " — вариант № " + number)
        for para in paragraphs:
            ET.SubElement(section, ns("p")).text = para
    return ET.tostring(book, encoding="utf-8", xml_declaration=True)


def build_one(key: str, target: Path) -> dict:
    page = SOURCES[key]["page"]
    html, raw, url = fetch_source(page)
    parts = extract_real_tale(html, key)
    fb2 = build_fb2(key, parts)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(fb2)
    payload = {
        "book": key,
        "title": SOURCES[key]["title"],
        "source_url": BASE + "/wiki/" + urllib.parse.quote(page, safe="/"),
        "retrieved_url": url,
        "source_sha256": sha256(raw),
        "fb2_sha256": sha256(fb2),
        "chapters": len(parts),
        "section_numbers": [number for number, _ in parts],
        "paragraphs": sum(len(paras) for _, paras in parts),
        "source_chars": sum(len(p) for _, ps in parts for p in ps),
        "text_sha256": sha256("\n\n".join(
            p for _, ps in parts for p in ps).encode("utf-8")),
        "language": "ru",
        "origin": "Historic Russian folk tale, A. N. Afanasyev (1826-1871)",
        "status": "BOOK_ONLY_NOT_PLAYABLE",
        "ai_calls": 0,
    }
    if payload["source_chars"] < SOURCES[key]["min_cyrillic"]:
        raise ValueError("FB2 shorter than the historical source bound")

    # Each original numbered edition is an ALTERNATIVE telling, not the next
    # chronological act. The playable-input benchmark must select one full
    # version without silently merging incompatible histories.
    primary = SOURCES[key]["standalone_variant"]
    version = [part for part in parts if part[0] == primary]
    if len(version) != 1:
        raise ValueError("Selected historical edition is absent")
    standalone_title = SOURCES[key]["title"] + " — вариант № " + primary
    single = build_fb2(key, version, book_title=standalone_title)
    single_file = target.with_name(key + "_story.fb2")
    single_file.write_bytes(single)
    single_meta = {
        "book": key,
        "title": standalone_title,
        "source_url": payload["source_url"],
        "source_sha256": payload["source_sha256"],
        "parent_fb2_sha256": payload["fb2_sha256"],
        "fb2_sha256": sha256(single),
        "selected_variant": primary,
        "section_numbers": [primary],
        "chapters": 1,
        "paragraphs": len(version[0][1]),
        "source_chars": sum(len(p) for p in version[0][1]),
        "text_sha256": sha256("\n\n".join(version[0][1]).encode("utf-8")),
        "language": "ru",
        "status": "BOOK_ONLY_NOT_PLAYABLE",
        "ai_calls": 0,
        "edition_review_required": True,
    }
    if single_meta["source_chars"] < 700:
        raise ValueError("Standalone historical edition is truncated")
    single_file.with_suffix(".json").write_text(
        json.dumps(single_meta, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    payload["standalone_variant"] = primary
    payload["standalone_fb2_sha256"] = single_meta["fb2_sha256"]
    return payload


def main() -> None:
    arg = argparse.ArgumentParser(description=__doc__)
    arg.add_argument("--output-dir", type=Path, required=True)
    args = arg.parse_args()
    metas = []
    for key in SOURCES:
        fb2_path = args.output_dir / (key + ".fb2")
        info = build_one(key, fb2_path)
        meta_path = args.output_dir / (key + ".json")
        meta_path.write_text(json.dumps(info, ensure_ascii=False,
                                        indent=2) + "\n", encoding="utf-8")
        metas.append(info)
        # A strict CI summary should never print original book paragraphs.
        print(key + ": " + str(info["chapters"]) + " original sections, " +
              str(info["paragraphs"]) + " paragraphs, sha256=" +
              info["fb2_sha256"] + "; standalone variant " +
              info["standalone_variant"] + " sha256=" +
              info["standalone_fb2_sha256"])
    if metas[0]["fb2_sha256"] == metas[1]["fb2_sha256"]:
        raise ValueError("Two independent source books cannot have same hash")


if __name__ == "__main__":
    main()
