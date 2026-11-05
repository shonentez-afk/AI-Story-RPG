"""Bounded TXT/FB2 extraction; UTF-16 index compatible in shape with Dart.

Port of the pinned importer/indexer, not a claim of executed Dart parity.
No images decoded, ZIP extraction, network, model calls or source execution.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from .common import AuthoringError, digest, require, utf16_len

MAX_SOURCE_BYTES = 20 * 1024 * 1024
MAX_CHUNKS = 30000
PART_WORDS = ("первый", "второй", "третий", "четвертый", "пятый",
              "шестой", "седьмой", "восьмой", "девятый", "десятый")
PART = re.compile(r"^(?:рассказ|история)\s+(" + "|".join(PART_WORDS)
                  + r")(?=$|[\s,.:;—-])", re.IGNORECASE)
# Dart String.trim uses the Unicode White_Space set plus BOM (not Python's
# extra C0 separators U+001C..U+001F).
TRIM = "\t\n\v\f\r \x85\xa0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"


def trim(text: str) -> str:
    return text.strip(TRIM)


def decode(filename: str, raw: bytes) -> str:
    require(0 < len(raw) <= MAX_SOURCE_BYTES, "source_size", "Empty or oversized book")
    specified = None
    try:
        if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
            return raw.decode("utf-16")
        if filename.lower().endswith(".fb2"):
            match = re.search(r'''encoding\s*=\s*["']([^"']+)["']''',
                              raw[:256].decode("latin-1"), re.IGNORECASE)
            specified = match[1].lower().replace("_", "-") if match else None
        if specified in ("windows-1251", "cp1251", "windows1251"):
            return raw.decode("cp1251")
        require(specified in (None, "utf-8", "utf8"), "unsupported_encoding",
                "Supported: UTF-8, Windows-1251 or BOM-marked UTF-16")
        try:
            return raw.decode("utf-8-sig")
        except UnicodeError:
            require(specified is None, "invalid_encoding", "Declared UTF-8 is invalid")
            text = raw.decode("cp1251")
            require(len(re.findall("[А-Яа-яЁё]", text)) >= 3 and "\0" not in text,
                    "invalid_encoding", "Cannot identify the book encoding")
            return text
    except UnicodeError as exc:
        raise AuthoringError("invalid_encoding", "Malformed book encoding") from exc


def _local(node) -> str:
    return node.tag.rsplit("}", 1)[-1] if isinstance(node.tag, str) else ""


def _children(node, tag):
    return [] if node is None else [x for x in node if _local(x) == tag]


def _first(node, tag):
    return next(iter(_children(node, tag)), None)


def _text(node) -> str:
    return "" if node is None else "".join(node.itertext())


def _block(kind, text="", resource=None):
    return {"kind": kind, "text": text, "resource_id": resource}


def _append(node, blocks):
    name = _local(node)
    if name == "title":
        text = trim(_text(node))
        if text:
            blocks.append(_block("heading", text))
    elif name == "image":
        ref = next((v[1:] for k, v in node.attrib.items()
                    if k.rsplit("}", 1)[-1] == "href" and v.startswith("#")), None)
        if ref is not None:
            blocks.append(_block("image", resource=ref))
    elif name in ("p", "subtitle", "v"):
        buffer = node.text or ""

        def flush(value):
            value = trim(value)
            if value:
                blocks.append(_block("heading" if name == "subtitle" else "paragraph", value))

        for part in node:
            if _local(part) == "image":
                flush(buffer)
                buffer = ""
                _append(part, blocks)
            else:
                buffer += _text(part)
            buffer += part.tail or ""
        flush(buffer)
    else:
        for part in node:
            _append(part, blocks)


def _split_parts(blocks):
    markers = []
    for i, block in enumerate(blocks):
        match = PART.match(trim(block["text"]).lower().replace("ё", "е"))
        if block["kind"] != "image" and match:
            markers.append((i, PART_WORDS.index(match[1]) + 1))
    if len(markers) < 3 or [n for _, n in markers] != list(range(1, len(markers) + 1)):
        return [blocks]
    starts = [0] + [i for i, _ in markers[1:]] + [len(blocks)]
    return [blocks[a:b] for a, b in zip(starts, starts[1:])]


def _preserve_xml_whitespace(source: str) -> str:
    """Protect text/attribute whitespace from Expat's XML normalization.

    Dart xml 6.6.1 preserves raw CR/CRLF in text. XML character references
    preserve those characters through ElementTree as well. Markup whitespace
    must stay markup. The pinned Dart importer can silently lose direct CDATA
    in paragraphs, so those sources are explicitly refused, never truncated
    to imitate that behavior. The real parser still validates the document.
    """
    result = []
    cursor = 0
    depth = 0
    while cursor < len(source):
        if source.startswith("<![CDATA[", cursor):
            raise AuthoringError("unsupported_fb2_cdata",
                                 "The current app does not preserve all FB2 CDATA text. "
                                 "This source cannot be indexed compatibly without losing text.")
        elif source.startswith("<!--", cursor) or source.startswith("<?", cursor):
            marker = "-->" if source.startswith("<!--", cursor) else "?>"
            end = source.find(marker, cursor + len(marker))
            require(end >= 0, "invalid_fb2", "Unterminated XML comment or processing instruction")
            result.append(source[cursor:end + len(marker)])
            cursor = end + len(marker)
        elif source[cursor] == "<":
            tag_start = cursor
            quote = None
            while cursor < len(source):
                char = source[cursor]
                if quote is not None:
                    if char == quote:
                        quote = None
                    result.append({"\r": "&#13;", "\n": "&#10;", "\t": "&#9;"}.get(char, char))
                else:
                    result.append(char)
                    if char in ("'", '"'):
                        quote = char
                    elif char == ">":
                        cursor += 1
                        break
                cursor += 1
            tag = source[tag_start:cursor]
            if tag.startswith("</"):
                depth -= 1
            elif not tag.endswith("/>"):
                depth += 1
        else:
            end = source.find("<", cursor)
            if end < 0:
                end = len(source)
            text = source[cursor:end]
            result.append(text.replace("\r", "&#13;") if depth > 0 else text)
            cursor = end
    return "".join(result)


def parse_book(filename: str, raw: bytes) -> dict:
    filename = Path(filename).name
    extension = Path(filename).suffix.lower()
    require(extension in (".txt", ".fb2"), "unsupported_format",
            "This authoring version accepts TXT and FB2; ZIP/EPUB are not enabled")
    source = decode(filename, raw)
    title = Path(filename).stem
    if extension == ".txt":
        if source.startswith("\ufeff"):
            source = source[1:]
        require(bool(trim(source)), "empty_source", "No text in the book")
        return {"title": title, "author": "", "chapters": [
            {"chapter_id": "chapter_0", "blocks": [_block("paragraph", source)]}]}
    # Decode first so UTF-16 cannot hide a DTD from this check. DTDs and
    # entities are unsupported; ordinary &amp;/numeric XML references work.
    require(not re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", source, re.IGNORECASE),
            "unsafe_xml", "FB2 with DTD/entity declarations is not accepted")
    prepared = _preserve_xml_whitespace(source)
    try:
        root = ET.fromstring(prepared)
    except (ET.ParseError, ValueError) as exc:
        raise AuthoringError("invalid_fb2", "Malformed FB2 XML") from exc
    require(_local(root) == "FictionBook", "invalid_fb2", "Expected FictionBook root")
    # Bound nesting before the recursive order-preserving traversal.
    stack = [(root, 0)]
    count = 0
    while stack:
        node, depth = stack.pop()
        count += 1
        require(depth <= 128 and count <= 200000, "xml_complexity", "FB2 is too complex")
        stack.extend((part, depth + 1) for part in node)
    info = _first(_first(root, "description"), "title-info")
    title = trim(_text(_first(info, "book-title"))) or title
    authors = []
    for author in _children(info, "author"):
        name = " ".join(filter(None, [trim(_text(_first(author, part)))
                                     for part in ("first-name", "middle-name", "last-name")]))
        if name:
            authors.append(name)
    chapters = []

    def add(blocks):
        if blocks:
            chapters.append({"chapter_id": f"chapter_{len(chapters)}", "blocks": blocks})

    auxiliary = []
    for body in _children(root, "body"):
        role = trim(body.get("name", "")).lower()
        if role in ("notes", "comments"):
            auxiliary.append(body)
            continue
        sections = _children(body, "section")
        if not sections:
            blocks = []
            _append(body, blocks)
            add(blocks)
        for section in sections:
            blocks = []
            _append(section, blocks)
            for part in _split_parts(blocks):
                add(part)
    for body in auxiliary:
        blocks = [_block("heading", "Примечания" if trim(body.get("name", "")).lower()
                         == "notes" else "Комментарии")]
        _append(body, blocks)
        if len(blocks) > 1:
            add(blocks)
    return {"title": title, "author": ", ".join(authors), "chapters": chapters}


def make_index(book: dict, max_chunk_utf16: int = 4096) -> dict:
    require(type(max_chunk_utf16) is int and 256 <= max_chunk_utf16 <= 12000,
            "invalid_chunk_size", "Chunk size must be 256..12000 UTF-16 units")
    require(bool(trim(book["title"])) and 0 < len(book["chapters"]) <= 10000,
            "invalid_book", "Book needs a title and 1..10000 chapters")
    chunks, chapters = [], []
    total = media = 0
    for ci, chapter in enumerate(book["chapters"]):
        length = text_blocks = images = 0
        first_chunk = len(chunks)
        for bi, block in enumerate(chapter["blocks"]):
            if block["kind"] == "image":
                images += 1
                continue
            text = block["text"]
            if not text:
                continue
            units = text.encode("utf-16-le")
            size = len(units) // 2
            length += size
            text_blocks += 1
            require(total + length <= MAX_SOURCE_BYTES, "source_size", "Too much extracted text")
            start = part = 0

            def unit(i):
                return units[2 * i] | units[2 * i + 1] << 8

            while start < size:
                end = min(start + max_chunk_utf16, size)
                if end < size:
                    if 0xDC00 <= unit(end) <= 0xDFFF:
                        end -= 1
                    minimum = start + ((end - start) * 6 // 10)
                    for i in range(end - 1, minimum - 1, -1):
                        if unit(i) in (10, 32, 9, 46, 33, 63, 0x3002, 0xFF01, 0xFF1F):
                            choice = i + 1
                            if choice < size and not 0xDC00 <= unit(choice) <= 0xDFFF:
                                end = choice
                                break
                piece = units[2 * start:2 * end].decode("utf-16-le")
                require(len(chunks) < MAX_CHUNKS, "too_many_chunks", "Too many source chunks")
                chunks.append({"id": f"c{ci}_b{bi}_p{part}", "chapter_index": ci,
                               "chapter_id": chapter["chapter_id"], "block_index": bi,
                               "start_utf16": start, "end_utf16": end, "text": piece,
                               "sha256_text": digest(piece.encode("utf-8")),
                               "analysis_status": "PENDING"})
                start = end
                part += 1
        chapters.append({"chapter_index": ci, "chapter_id": chapter["chapter_id"],
                         "text_utf16_total": length, "text_utf16_indexed": length,
                         "text_blocks": text_blocks, "media_blocks_for_review": images,
                         "source_chunks": len(chunks) - first_chunk, "text_indexed": length > 0})
        total += length
        media += images
    require(total > 0, "empty_source", "No extractable book text")
    # Insertion order intentionally matches Dart jsonEncode; don't sort keys.
    fingerprint = digest(json.dumps(book, ensure_ascii=False, separators=(",", ":"),
                                    allow_nan=False).encode("utf-8"))
    return {"format": "ai_story_source_index_v1", "schema_version": 1,
            "source_fingerprint": fingerprint, "fingerprint_scope": "normalized_parsed_content",
            "title": book["title"], "author": book["author"], "chapter_count": len(chapters),
            "indexed_chapter_count": sum(c["text_indexed"] for c in chapters),
            "text_indexed_utf16": total, "text_total_utf16": total,
            "media_blocks_for_review": media, "gameplay_coverage": 0,
            "can_publish_bookworld": False, "stage": "SOURCE_INDEX_ONLY",
            "chapters": chapters, "chunks": chunks}
