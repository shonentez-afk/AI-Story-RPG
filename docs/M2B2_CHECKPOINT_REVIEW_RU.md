# M2b2 — приватные checkpoints и проверка упоминаний в единой библиотеке

Дата: 2026-11-02. Ветка: `feat/m2b2-private-checkpoints-review-20261102`.

## Что реально добавлено
- `apps/story_reader/lib/source_analysis_checkpoint_repository.dart` сохраняет M2b1 checkpoint в приватном `ApplicationSupport/ai_story_source_analysis_v1/<source_fingerprint>.json` Android/Windows. ID — только SHA-256 из M2a; путь нельзя подменить `../`. Обычный импорт книги и её файл в `BookStorage` не переписываются.
- Перед каждой заменой создаётся временный файл в той же папке, данные сбрасываются на диск, затем файл переименовывается. При сбое предыдущая корректная контрольная точка не заменяется неполным JSON. Физическое отключение питания, реальная ФС Windows/Android и многопроцессная конкуренция **не проверены**. SHA-256 — контроль целостности, а не подпись/авторство.
- `SourceIndexPreviewPage` остаётся **единственным** экраном подготовки из существующей библиотеки. После индексации он проверяет и поднимает checkpoint для строго той же нормализованной редакции/нарезки. Есть ручная обработка порций в `Isolate.run`, прогресс, retry, reset только с подтверждением и явная ошибка при повреждённом checkpoint. Публикация состояния UI происходит **после** успешного сохранения; при ошибке пользователь сохраняет прежний прогресс.
- Упоминания по простым локальным шаблонам (`CHARACTER_NAME`, `LOCATION_NAME`) скрыты до нажатия «Показать упоминания (возможны спойлеры)». Пользователь подтверждает/отклоняет само **упоминание с точным source span**, а не факты, связи, тайны, сюжет или игровые действия. Список ленивый, до 40 находок за раз. Персонажи/локации с иными языковыми конструкциями пока могут быть пропущены.
- `processBatch` стал линейным на одну порцию и атомарным в памяти; replay/decode перестали делать O(chunks × mentions) поиск. Проверки span/hash/номера книги и `gameplay_coverage=0`, `can_publish_bookworld=false` сохранены.

## Тесты и регрессия
- `apps/story_reader/test/source_analysis_checkpoint_test.dart`: атомарная замена, чтение, повторное открытие, неверный fingerprint/путь, неудачная запись, скрытые спойлеры, повреждённый checkpoint и подтверждённый сброс.
- `apps/story_reader/test/book_source_index_test.dart`: M2a работает с injected in-memory checkpoint; existing UI не требует реальный path_provider в тестах.
- Выполнить полный GitHub Actions Flutter analyze/widget, Python/Dart/story-core и обе платформенные сборки по **фактическому HEAD**. Пока нет зелёного CI, статус: CODE, QA PENDING.

## Явные ограничения
Это **не** генерация playable RPG по пользовательскому роману. НЕТ автоматического извлечения фактов и событий, алиасов, канонической хронологии, вычисления gameplay coverage, AI, intermediate blueprint и публикации .bworld. НЕТ физического E2E Android/Windows, TalkBack/Narrator/rotation и power-loss. Не удалять legacy TXT/FB2, .bwsave v1/v2, BookWorld campaigns. Не включать второй импорт или библиотеку.

Следующее M2b3: детальные схемы evidence/facts/events/relationships с source refs и INFERRED/CONFIRMED/CONFLICTED/INVENTED, анализ через сменяемого провайдера только при явном согласии и локальный baseline, совместное сопоставление глав, review и spoiler gating. Отдельно performance и SQLite incremental checkpoints для 20 МиБ/30k chunks — текущий JSON snapshot перезаписывается после порций и может быть тяжёлым для крупных книг.
