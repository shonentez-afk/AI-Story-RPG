#!/usr/bin/env python3
"""Build a complete REAL Brothers Grimm FB2 regression fixture from Gutenberg #2591.

Downloads one explicitly identified public-domain English edition over HTTPS
for CI.  The downloaded book, transformed FB2 and manifest remain LOCAL and
are NOT committed, uploaded as test artifacts or included in APK/EXE.

Not a fake "Grimm-like" book: every story and its actual text is required.
Python standard library only.  Supports --input for offline reproducibility.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

SOURCE_URL = "https://www.gutenberg.org/cache/epub/2591/pg2591.txt"
SOURCE_FALLBACK = "https://www.gutenberg.org/ebooks/2591.txt.utf-8"
EXPECTED_TALES = 62
MIN_BOOK_CHARACTERS = 280_000
MIN_PARAGRAPHS = 500
MAX_SOURCE_BYTES = 4 * 1024 * 1024
FB2_NAMESPACE = "http://www.gribuser.ru/xml/fictionbook/2.0"
FB2_TITLE = "Grimms' Fairy Tales (Project Gutenberg 2591, full CI corpus)"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download_source() -> tuple[bytes, str]:
    errors = []
    for url in (SOURCE_URL, SOURCE_FALLBACK):
        for attempt in range(2):
            try:
                request = urllib.request.Request(
                    url,
                    headers={"User-Agent": "AI-Story-RPG-public-domain-CI/1.0"},
                )
                with urllib.request.urlopen(request, timeout=35) as response:
                    final_url = response.geturl()
                    if not final_url.startswith("https://"):
                        raise ValueError("Insecure Gutenberg redirect")
                    data = response.read(MAX_SOURCE_BYTES + 1)
                if len(data) > MAX_SOURCE_BYTES:
                    raise ValueError("Full book exceeds download size bound")
                if len(data) < MIN_BOOK_CHARACTERS:
                    raise ValueError("Downloaded book is incomplete")
                return data, final_url
            except (OSError, ValueError, urllib.error.URLError) as exc:
                errors.append(type(exc).__name__)
                if attempt == 0:
                    time.sleep(2)
    raise RuntimeError(
        "Cannot fetch full public-domain Grimm corpus: " + ",".join(errors)
        + "; CI must FAIL, not silently SKIP or replace the source with synthetic text."
    )


def extract_tales(source: str) -> list[tuple[str, list[str]]]:
    text = source.replace("\r\n", "\n").replace("\r", "\n").lstrip("\ufeff")
    start = re.search(
        r"(?m)^\*\*\* START OF (?:THE|THIS) PROJECT GUTENBERG EBOOK .+? \*\*\*\s*$",
        text,
    )
    end = re.search(
        r"(?m)^\*\*\* END OF (?:THE|THIS) PROJECT GUTENBERG EBOOK .+? \*\*\*\s*$",
        text,
    )
    if start is None or end is None or end.start() <= start.end():
        raise ValueError("Gutenberg header/footer markers not found")
    original = text[start.end():end.start()]
    if "Grimms" not in original[:1000] or "Edgar Taylor" not in original[:1400]:
        raise ValueError("Edition or historical translation not recognized")
    toc = re.search(
        r"(?s)\bCONTENTS:\s*\n(.*?)\n\s*THE BROTHERS GRIMM FAIRY TALES\s*\n",
        original,
    )
    if toc is None:
        raise ValueError("Gutenberg #2591 table of contents not found")
    titles = []
    for line in toc.group(1).splitlines():
        title = line.strip()
        if (title.isupper() and title[:1].isalpha()
                and title not in {"FIRST STORY", "SECOND STORY"}
                and title not in titles):
            titles.append(title)
    if len(titles) != EXPECTED_TALES:
        raise ValueError(
            f"Expected all {EXPECTED_TALES} original tales, found {len(titles)}"
        )
    story_body = original[toc.end():]
    locations = []
    search_from = 0
    for title in titles:
        matcher = re.search(
            r"(?m)^[ \t]*" + re.escape(title) + r"[ \t]*$",
            story_body[search_from:],
        )
        if matcher is None:
            raise ValueError(f"Missing full story heading: {title}")
        begin = search_from + matcher.start()
        end_of_heading = search_from + matcher.end()
        locations.append((title, begin, end_of_heading))
        search_from = end_of_heading
    tales = []
    for i, (title, begin, end_of_heading) in enumerate(locations):
        next_begin = locations[i + 1][1] if i + 1 < len(locations) else len(story_body)
        chapter = story_body[end_of_heading:next_begin].strip()
        paragraphs = []
        for part in re.split(r"\n[ \t]*\n+", chapter):
            cleaned = re.sub(r"[ \t]*\n[ \t]*", " ", part).strip()
            if cleaned:
                paragraphs.append(cleaned)
        if not paragraphs or sum(len(p) for p in paragraphs) < 250:
            raise ValueError(f"Truncated full story: {title}")
        tales.append((title, paragraphs))
    characters = sum(len(p) for _, ps in tales for p in ps)
    paragraphs = sum(len(ps) for _, ps in tales)
    if characters < MIN_BOOK_CHARACTERS or paragraphs < MIN_PARAGRAPHS:
        raise ValueError(
            f"Incomplete Gutenberg text: {characters} chars, {paragraphs} paragraphs"
        )
    return tales


def build_fb2(tales: list[tuple[str, list[str]]]) -> bytes:
    def tag(name: str) -> str:
        return "{" + FB2_NAMESPACE + "}" + name

    ET.register_namespace("", FB2_NAMESPACE)
    book = ET.Element(tag("FictionBook"))
    description = ET.SubElement(book, tag("description"))
    title_info = ET.SubElement(description, tag("title-info"))
    ET.SubElement(title_info, tag("book-title")).text = FB2_TITLE
    for given_name in ("Jacob", "Wilhelm"):
        author = ET.SubElement(title_info, tag("author"))
        ET.SubElement(author, tag("first-name")).text = given_name
        ET.SubElement(author, tag("last-name")).text = "Grimm"
    ET.SubElement(title_info, tag("lang")).text = "en"
    body = ET.SubElement(book, tag("body"))
    for title, paragraphs in tales:
        section = ET.SubElement(body, tag("section"))
        title_tag = ET.SubElement(section, tag("title"))
        ET.SubElement(title_tag, tag("p")).text = title
        for paragraph in paragraphs:
            ET.SubElement(section, tag("p")).text = paragraph
    return ET.tostring(book, encoding="utf-8", xml_declaration=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="Local Gutenberg TXT; no network")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    if args.input:
        raw, source_location = args.input.read_bytes(), str(args.input)
    else:
        raw, source_location = download_source()
    if len(raw) > MAX_SOURCE_BYTES:
        raise ValueError("Source too large")
    source_text = raw.decode("utf-8-sig")
    tales = extract_tales(source_text)
    fb2 = build_fb2(tales)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(fb2)
    manifest = {
        "source": source_location,
        "gutenberg_id": 2591,
        "translation": "Edgar Taylor and Marian Edwardes",
        "source_sha256": sha256(raw),
        "fb2_sha256": sha256(fb2),
        "tales": len(tales),
        "paragraphs": sum(len(ps) for _, ps in tales),
        "source_chars": sum(len(p) for _, ps in tales for p in ps),
        "titles": [title for title, _ in tales],
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "FULL Gutenberg #2591 -> FB2: "
        f"{manifest['tales']} tales, {manifest['paragraphs']} paragraphs, "
        f"{manifest['source_chars']} actual characters; "
        f"source sha256={manifest['source_sha256']}, "
        f"FB2 sha256={manifest['fb2_sha256']}"
    )


if __name__ == "__main__":
    main()
