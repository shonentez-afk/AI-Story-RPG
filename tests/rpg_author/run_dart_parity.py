"""CI-only, read-only checks against REAL Dart source/blueprint implementations.

Run from repo root after `dart pub get` in tests/rpg_author/dart. All input
texts are original synthetic fixtures. No user's book is sent to CI.
"""
import base64
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.rpg_author.source_adapter import make_index, parse_book
from tools.rpg_author.common import AuthoringError
from tools.rpg_author.validate import candidate_blueprint
from tests.rpg_author.fixtures import source, story


def dart(request):
    result = subprocess.run(["dart", "run", "probe.dart"], cwd=ROOT / "tests/rpg_author/dart",
                            input=json.dumps(request, ensure_ascii=False), encoding="utf-8",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def main():
    fb2 = '''<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
    <description><title-info><book-title>Тест &amp; книга 😀</book-title>
    <author><first-name>Анна</first-name><last-name>Автор</last-name></author>
    </title-info></description><body><section><title><p>Глава</p></title>
    <p>До <emphasis>света</emphasis><image href="#x"/> после.</p>
    <section><p>Строка\r\nпродолжение.</p><v>Стих.</v></section></section></body>
    <body name="notes"><section><title><p>1</p></title><p>Сноска.</p></section></body>
    </FictionBook>'''
    numbered = '<FictionBook><body><section>' + ''.join(
        f'<p>Рассказ {word}</p><p>Текст.</p>' for word in ('первый', 'второй', 'третий')) + '</section></body></FictionBook>'
    inputs = [
        ("plain.txt", " \r\nС😀.\t\n" * 200, "utf-8-sig"),
        ("boundary.txt", "я" * 255 + "😀" + "б" * 100, "utf-8"),
        ("old.txt", "Старинный текст книги.", "cp1251"),
        ("utf16.txt", "Строка 😀\nВторая.", "utf-16"),
        ("structured.fb2", fb2, "utf-8"),
        ("numbered.fb2", numbered, "utf-8"),
        ("old.fb2", '<?xml version="1.0" encoding="windows-1251"?>' + numbered, "cp1251"),
        ("utf16.fb2", numbered, "utf-16"),
        ("media.fb2", '<FictionBook><body><section><image href="#x"/></section><section><p>Текст.</p></section></body></FictionBook>', "utf-8"),
        ("inline.fb2", '<FictionBook><body><p>А<strong>В</strong><!-- comment -->Г &#x1f600;.</p></body></FictionBook>', "utf-8"),
        ("whitespace.fb2", '<FictionBook>\r\n<body><p>Один\rдва.</p><p>А\r\n&lt;&amp; Б</p><image href="#name\r\nwith\ttabs"/></body></FictionBook>', "utf-8"),
    ]
    checked = 0
    for filename, text, encoding in inputs:
        data = text.encode(encoding)
        for chunk_size in (257, 4096):
            expected = make_index(parse_book(filename, data), chunk_size)
            actual = dart({"operation": "source", "filename": filename,
                           "data": base64.b64encode(data).decode(), "chunk_size": chunk_size})
            if actual != expected:
                keys = [k for k in expected if actual.get(k) != expected[k]]
                raise AssertionError(f"{filename}, chunk={chunk_size}: differing fields {keys}\n"
                                     f"Dart: {json.dumps(actual, ensure_ascii=False)}\n"
                                     f"Python: {json.dumps(expected, ensure_ascii=False)}")
            checked += 1
    blueprint = candidate_blueprint(story(), source())
    result = dart({"operation": "blueprint", "blueprint": blueprint})
    assert result == {"book_id": blueprint["book_id"], "scene_count": len(blueprint["scenes"])}
    # Regression from real Dart comparison: the native parser drops direct
    # CDATA inside p. Do not delete it in Python just to make indices equal.
    cdata = '<FictionBook><body><p>А<![CDATA[Б]]>В</p></body></FictionBook>'
    try:
        parse_book("cdata.fb2", cdata.encode())
    except AuthoringError as error:
        assert error.code == "unsupported_fb2_cdata"
    else:
        raise AssertionError("CDATA would silently lose content in the current app")
    print(json.dumps({"source_comparisons": checked, "candidate_accepted_by_dart_blueprint": True,
                      "known_lossy_source_forms_refused": 1,
                      "application_modified": False, "external_ai_package_built": False}))


if __name__ == "__main__":
    main()
