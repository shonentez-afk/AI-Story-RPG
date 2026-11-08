# E6g — синхронизация с актуальным native PR #133 (8 ноября 2026)

**Назначение:** только внешний генератор и его тесты, сохранены оба родительских коммита; не merge в main и не изменение native engine.

- Ранее проверенный E6g: `c6da44b394616ab0f0e572ac142a89fe4c9c6fb2`; source-locked native база: `7c4401c25b77e4643cf23000c28a717cb22dabca`.
- Проверенный native PR #133 HEAD при синхронизации: `233c6c31abeae0768c36a60c4dd3add94916ec03` (Draft).
- Audit Git comparison: из 27 locked blobs реально изменились **два**, и их изменения изучены до замены pin:
  1. `apps/story_reader/lib/world_library_gateway.dart`: транспорт и его models перенесены в новый независимый `package:rpg_gameplay`; Flutter-файл теперь реэкспортирует старые имена WorldLibrary*/WorldGameView, а SQLite/gameplay остаются в independent runtime. Старый файл был ~745 строк; новый ~99. Это архитектурное перемещение, а не гарантия автоматической совместимости: проверяется реальными Dart/SQLite parity и native CI.
  2. `packages/story_authoring/lib/story_authoring.dart`: добавлены экспорты `quick_rpg_builder` и source-locked authoring/NPC/semantic функций; уже проверенные `BookImporter`, `BookSourceIndexer`, `BookAuthoringEngine` и native build-extended не удалены. Приёмка — через реальную Dart-проверку.
- Остальные 25 locked blobs по Git tree идентичны базовому SHA. Защита `contract_drift` сохранена fail-closed. `compatibility_v2` меняет **ровно два OID** и `application_baseline`.
- Внешний автор переносится без копирования main/apps/packages/tools/bookworld из старой E6g базы; новое native дерево — точный PR #133 HEAD, два родителя сохраняют историю.
- Проверять: `python3 -m tools.rpg_author doctor`; `python3 -m unittest discover -s tests/rpg_author -t .`; `python3 tests/rpg_author/run_dart_parity.py`; на GitHub exact-head `External RPG author tests` (author-tests + dart-parity) и native CI.
- До подтверждения CI: статус **INTEGRATION_PENDING**, не USER_READY. Реальные FB2, >192 scenes, initial-state review и Android/Windows device QA остаются отдельными блокерами.
