"""Build a public, original tiny source-bound v3 test package.

Not a book adaptation from a real author. No private documents or API keys.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import tempfile

from tests.rpg_author.fixtures import TEXT, analysis, story
from tests.rpg_author.fixtures_rich import enrichment
from tools.bookworld import private_rich_bookworld
from tools.rpg_author import project
from tools.rpg_author.common import canonical, digest
from tools.rpg_author.rich_package import build_rich, verify_rich_bundle


def main():
    cli = argparse.ArgumentParser()
    cli.add_argument("--output-dir", type=Path, required=True)
    args = cli.parse_args()
    output = args.output_dir.resolve()
    if output.exists():
        raise FileExistsError(f"Sample output already exists: {output}")
    output.mkdir(parents=True, mode=0o700)
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        source = root / "test_story.txt"
        source.write_text(TEXT, encoding="utf-8")
        work = root / "project"
        project.init_project(work, source)
        project.submit_analysis(work, analysis())
        project.submit_story(work, story())
        overlay = root / "rich_overlay.json"
        overlay.write_bytes(canonical(enrichment()))
        game = output / "River_Rich_Hero_v3.bworld"
        result = build_rich(work, overlay, game, model_id=None)
        verified = verify_rich_bundle(game, game.with_suffix(".attribution.json"))
        if verified["status"] != "rich_bundle_structurally_verified":
            raise RuntimeError("Rich bundle validation failed")
        if private_rich_bookworld.verify(game.read_bytes())["format_version"] != 3:
            raise RuntimeError("Not a real source-bound version 3 archive")
        (output / "rich_overlay.json").write_bytes(overlay.read_bytes())
    (output / "synthetic_story.txt").write_text(TEXT, encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(
        result["archive_sha256"] + "  River_Rich_Hero_v3.bworld\n",
        encoding="ascii",
    )
    (output / "README_RU.txt").write_text(
        "ТЕСТ ГЕРОЙ / ПРЕДМЕТЫ / ЖУРНАЛ — приватный BookWorld v3\n"
        "Это короткий СИНТЕТИЧЕСКИЙ сюжет и проверка игровых механизмов,\n"
        "а не сказка братьев Гримм и не оценка художественного качества.\n\n"
        "Откройте v3 в сборке приложения с поддержкой rich v3\n"
        "(PR #96 включён в main; test-build-643 и последующие).\n\n"
        "Маршрут А: 'take_rope' / взять верёвку -> 'rescue' / спасти.\n"
        "Проверка: герой Лена, смелость растёт 1->2->4; верёвка появляется\n"
        "после первого хода и исчезает после второго; 'Мальчик спасён у реки'\n"
        "появляется в знаниях. Журнал содержит оба хода и реальные изменения.\n"
        "Маршрут Б: 'leave_rope' -> 'go_for_help'. Верёвки нет,\n"
        "наблюдательность растёт 1->2; журнал содержит два других решения.\n"
        "После перезапуска и переноса .bwsave состояние должно совпадать.\n\n"
        "Реальная атрибуция ChatGPT/OpenAI записана в v3 в обеих частях\n"
        "архива, а отдельный .attribution.json связан по SHA256.\n"
        "ID модели не объявлен достоверным: not_attested.\n"
        "Разрешение на публикацию чужой книги не предоставлено.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
