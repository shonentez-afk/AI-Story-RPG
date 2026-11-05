"""Build a small PUBLIC synthetic example, never private user content.

The sample is a mechanics/ZIP importer test, not a model-generated artistic
adaptation and not a claim that ChatGPT wrote the included sample prose.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import tempfile

from tools.rpg_author import project
from tools.rpg_author.legacy_package import build_legacy, verify_bundle
from tests.rpg_author.fixtures import TEXT, analysis, story


def main() -> None:
    cli = argparse.ArgumentParser()
    cli.add_argument("--output-dir", type=Path, required=True)
    args = cli.parse_args()
    target_dir = args.output_dir.resolve()
    if target_dir.exists():
        raise FileExistsError(f"Refusing to overwrite example folder: {target_dir}")
    target_dir.mkdir(parents=True, mode=0o700)
    with tempfile.TemporaryDirectory() as temporary:
        base = Path(temporary)
        text_file = base / "test_story.txt"
        text_file.write_text(TEXT, encoding="utf-8")
        project_dir = base / "project"
        project.init_project(project_dir, text_file)
        project.submit_analysis(project_dir, analysis())
        project.submit_story(project_dir, story())
        bookworld = target_dir / "synthetic_river_trial.bworld"
        build_legacy(project_dir, bookworld, acknowledgement=True)
        verified = verify_bundle(bookworld, bookworld.with_suffix(".attribution.json"))
        if verified["status"] != "bundle_structurally_verified":
            raise RuntimeError("Expected a structurally verified archive")
    (target_dir / "synthetic_story.txt").write_text(TEXT, encoding="utf-8")
    (target_dir / "README_RU.txt").write_text(
        "СИНТЕТИЧЕСКИЙ ПРИМЕР для проверки импорта, не литературная игра.\n"
        "История и сценарий — фиксированные тестовые данные, НЕ результат вызова ChatGPT.\n"
        "Атрибуция — демонстрация старого ограниченного формата, не подтверждение\n"
        "реального вызова модели. model_id=null / not_attested.\n"
        "Импортировать только .bworld, оставив .attribution.json рядом как\n"
        "отдельное раскрытие. Приложение не проверяет файл атрибуции.\n"
        "Публичное распространение адаптации не разрешено. Это приватная проба.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
