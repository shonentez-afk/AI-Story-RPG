"""Strict JSON and bounded files used by the offline authoring commands."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MAX_JSON_BYTES = 64 * 1024 * 1024
IDENTIFIER = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
DIGEST = re.compile(r"^[a-f0-9]{64}$")


class AuthoringError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def require(condition: bool, code: str, message: str):
    if not condition:
        raise AuthoringError(code, message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def utf16_len(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


def fields(value, expected: set[str], where: str):
    require(type(value) is dict and set(value) == expected, "invalid_fields",
            f"{where}: expected fields {', '.join(sorted(expected))}")


def string(value, where: str, limit: int, *, empty: bool = False):
    require(isinstance(value, str), "invalid_text", f"{where}: expected text")
    try:
        size = utf16_len(value)
    except UnicodeError as exc:
        raise AuthoringError("invalid_unicode", f"{where}: invalid Unicode") from exc
    require(size <= limit and (empty or bool(value.strip())), "invalid_text",
            f"{where}: empty or longer than {limit} UTF-16 units")


def identifier(value, where: str):
    require(isinstance(value, str) and bool(IDENTIFIER.fullmatch(value)),
            "invalid_id", f"{where}: invalid identifier")


def string_list(value, where: str, limit: int):
    require(type(value) is list and len(value) <= limit
            and all(isinstance(x, str) for x in value), "invalid_list",
            f"{where}: expected at most {limit} strings")
    require(len(set(value)) == len(value), "duplicate_id", f"{where}: duplicates")


def read_bytes(path: Path, limit: int = MAX_JSON_BYTES) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    require(len(data) <= limit, "file_too_large", f"File exceeds {limit} bytes")
    return data


def parse_json(data: bytes):
    def pairs(values):
        result = {}
        for key, value in values:
            require(key not in result, "duplicate_json_key", f"Duplicate key: {key}")
            result[key] = value
        return result

    def invalid_constant(value):
        raise AuthoringError("invalid_json", f"Invalid JSON number: {value}")

    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=pairs,
                          parse_constant=invalid_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise AuthoringError("invalid_json", "Expected bounded UTF-8 JSON") from exc


def read_json(path: Path):
    return parse_json(read_bytes(path))


def outside_repository(path: Path) -> Path:
    path = path.expanduser().resolve()
    require(path != ROOT and ROOT not in path.parents, "private_output_in_repository",
            "Keep books, projects and generated files outside the source checkout")
    return path


def atomic_write(path: Path, data: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".author-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
