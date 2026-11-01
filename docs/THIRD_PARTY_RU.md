# Аудит GitHub и реестр сторонних компонентов
**Проверено по публичным файлам GitHub:** 2026-11-01. Это анализ исходников/лицензий, не выполненные в нашей среде тесты интеграции. Перед копированием закреплять SHA, архив лицензии и attribution.

| Репозиторий | Лицензия / статус | Пригодность | Решение |
|---|---|---|---|
| [zenstory-ai/novel-to-game](https://github.com/zenstory-ai/novel-to-game) | MIT; LICENSE есть | Полноохватный анализ романа, SOURCE_BIBLE, игровая адаптация и QA; в основном **инструкции агенту**, не runtime-компилятор | **Методика и схемы**. При прямом копировании сохранить MIT. Контрольный SHA: `9dddcd2dfdf02d46da23b1050aa7e45dfac3fae9`. |
| [iamarxs/AnyWorld](https://github.com/iamarxs/AnyWorld) | MIT; LICENSE есть | Python LLM: tokenization.py, provider.py, compaction.py, auditing.py, response_schemas.py | **Адаптировать** для Python Book Compiler и тестов. Для общего Flutter runtime реализовать совместимый Dart-интерфейс, не тащить Python сервер в Android. Контрольный SHA: `312e025b376aad9e4a4c79f79891df24059673ce`. |
| [Stelliro/Morkyn](https://github.com/Stelliro/Morkyn) | PolyForm Noncommercial 1.0.0 | Windows упаковка, игровое состояние, QA, локальные модели | **Изучать идеи, код не копировать** в коммерчески независимую базу без разрешения. |
| [horizonfps/project-lunar](https://github.com/horizonfps/project-lunar) | README упоминает MIT, но явного LICENSE в проверенном корне нет и GitHub license=null | NPC/memory/сценарии, event_store, редактор | **Только идеи до прояснения прав.** |
| [nbarraud/plottwist](https://github.com/nbarraud/plottwist) | README упоминает MIT, файла LICENSE в проверенном корне нет | PDF->визуальная новелла | **Не переносить.** book_analyzer.py для больших книг берёт лишь несколько выборочных фрагментов, нарушает требование полного охвата. |
| [seewhydee/my-gm-is-ai](https://github.com/seewhydee/my-gm-is-ai) | GPL-3.0 | Сильная логика действий и hard-state | Изучение алгоритмов; **код не переносить** без принятия GPL-обязательств. |
| [docling-project/docling](https://github.com/docling-project/docling) | MIT | Импорт EPUB/PDF/DOCX и унифицированное представление | Python компилятор |
| [natasha/natasha](https://github.com/natasha/natasha) | MIT | Русскоязычные имена/NER/морфология; модель преимущественно новостная | Дополнительный анализ; не доверять без верификации |
| [BookNLP/booknlp](https://github.com/booknlp/booknlp) | MIT | Распознавание и объединение персонажей в английских книгах | Англоязычный анализ, не русский по умолчанию |
| [aerkalov/ebooklib](https://github.com/aerkalov/ebooklib) | AGPL-3.0+ | EPUB | Не включать без отдельного лицензионного решения; основной вариант Docling |
| [r0x0r/pywebview](https://github.com/r0x0r/pywebview) | BSD-3-Clause | Desktop оболочка | **Не требуется** при Flutter |
| [ollama/ollama](https://github.com/ollama/ollama) | MIT | Локальные модели | Позднее; подключать как внешний опциональный runtime |

## Что конкретно повторно использовать
- NovelToGame: `skills/novel-game-analyze/references/gameability-protocol.md`; `skills/game-world-design/references/narrative-design-method.md`; `skills/novel-to-game/references/pipeline-contract.md`; `scripts/validate_repo.py` как источник тестовых идей. Методика SOURCE_BIBLE с provenance и явным статусом каждого факта.
- AnyWorld: `logic/llm/tokenization.py`, `provider.py`, `compaction.py`, `response_schemas.py`, `auditing.py` и тесты. Система не является набором независимых файлов; зависимости требуют обособления и тестирования.
- Mørkyn: `docs/Packaging.md`, `docs/NarrationPipeline.md` и benchmarks — исключительно справочная информация.
- Project Lunar: `backend/app/db/event_store.py`, `backend/app/engines/npc_mind_engine.py`, `memory_engine.py` — справочные материалы.

## Правила при переносе
1. Никогда не считать открытый GitHub код автоматически совместимым по лицензии.
2. Текст собственной игры должен сохранять автономность от стороннего репозитория.
3. При прямом переносе: запись `source/revision/license/path` в provenance, notices рядом с поставкой, проверка и атрибуция модификаций.
4. Отдельно проверять лицензии модельных весов, TTS, изображений и прав на книги.
5. В README/STATUS говорить «анализировалось», а не «встроено», пока код не интегрирован и не прошёл тесты.

## Дополнение 2026-11-01: готовые текстовые RPG
Проведён отдельный исходный аудит движков Dart/Flutter и других IF-решений. **См. [TEXT_RPG_ENGINES_GITHUB_AUDIT_RU.md](TEXT_RPG_ENGINES_GITHUB_AUDIT_RU.md)**. Два кандидата для M0 spike: BSD-3-Clause `ErikSchultheiss/story_engine` (детерминированные условия, переходы, сохранения) и MIT `dennerkrans/ink_dart` + `flutter_ink` (компилированные Ink-сценарии и Flutter-виджеты). Выбор runtime до прохождения общих тестов не фиксирован. Код сторонних движков в репозиторий ещё не копировали.

## Добавление зависимости `crypto` для M1.6.6
- Пакет: `crypto ^3.0.6` от Dart project authors ([pub.dev crypto 3.0.6](https://pub.dev/packages/crypto/versions/3.0.6)), **BSD-3-Clause**. Применяется только для вычисления SHA-256 контрольной суммы переносимого пилотного сохранения.
- При поставке сохранять авторское уведомление и текст лицензии из поставляемого pub-пакета (BSD-3-Clause), включая `NOTICES`/лицензии Flutter dependencies. Собственный код проекта под BSD не переводится; чужая лицензия распространяется только на зависимость.
- SHA-256 здесь выявляет порчу байтов, но **не** доказывает, что файл создан доверенным пользователем или не был намеренно подменён.

## M1.6.6 — уточнение пакета для синхронизации локальных сохранений
- `shared_preferences_platform_interface ^2.4.2` — официальный Flutter plugin platform interface, BSD-3-Clause. Используется только для чтения активной `SharedPreferencesStorePlatform.instance` при синхронном выборе scoped очереди сериализации. Это предотвращает расхождение порядка операций и утечки между тестовыми бэкендами. Исходники или лицензия другого проекта не копируются.

## M1.7.1: зависимости проверяемого ядра и схемы
- `packages/story_core`: `crypto ^3.0.6` (Dart, BSD-3-Clause), уже используется Flutter-пилотом; `test ^1.25.15` — стандартный пакет Dart тестов, BSD-3-Clause, только dev dependency.
- GitHub Actions `story-core` устанавливает `jsonschema==4.23.0` (Python, MIT) для полноценной валидации JSON Schema 2020-12 и негативных тестов. Не входит в runtime Flutter и не является средством компиляции пользовательских книг.
- Собственный учебный сценарий и схема написаны для этого проекта; чужие сюжеты/исходный текст не копируются. Дистрибутив сохраняет положенные notices для реально поставляемых зависимостей.

## M1.7.2: сценарный координатор
Новый `packages/story_runtime_adapter` использует только уже выбранные `story_engine 0.1.0-alpha.1` (BSD-3-Clause), локальный собственный `story_core` и `test` (только dev). Внешний код не скопирован и приватные методы зависимостей не импортируются; обращение к StoryEngine происходит исключительно через публичный API. Реальных новых зависимостей внутри Android/Windows Flutter UI нет.

## M1.7.3 — native BookWorld import и compiler
- `packages/bookworld_format` использует `sqlite3 ^3.8.0` (Dart FFI, MIT; native hooks bundling SQLite для Android/Windows/Linux), `crypto ^3.0.6` (BSD-3-Clause) и собственный `story_core`. В этом пакете нет `archive`: проверка небольшого, ограниченного ZIP_STORED поднабора реализована своим Dart-кодом для отказа от двусмысленных/опасных ZIP особенностей.
- Отдельный Python-компилятор использует только стандартные `sqlite3`, `zipfile`, `hashlib`, `json`, `pathlib`; Python не входит в Flutter runtime. Для тестирования JSON Schema в CI есть прежняя dev-only зависимость `jsonschema==4.23.0` (MIT).
- Содержание demo оригинальное и создано для проекта, в `.bworld` нет исходного текста чужих книг или каких-либо приватных ключей/моделей/LLM-вызовов.
