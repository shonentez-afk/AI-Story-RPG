# M2b1 — возобновляемая локальная очередь анализа книги

Дата: 2026-11-02. Ветка: `feat/m2b1-resumable-provenance-20261102`.

## Область реализации
В `book_source_analysis.dart` добавлена чистая Dart очередь анализа фрагментов из M2a. Поддерживаются состояния PENDING/RUNNING/DONE/FAILED/REVIEW, ограниченная обработка порциями, ручной retry ошибок, checkpoint JSON с SHA-256 и восстановление RUNNING -> PENDING после прерывания. Доказательства имеют точные UTF-16 диапазоны в главе/блоке, SHA-256 текста и проверку исходного fingerprint. Отдельно отмечаем, что SHA — контроль целостности, а не аутентификация.

Локальный консервативный regex-сканер предлагает только *упоминания* имён (CHARACTER_NAME) и мест (LOCATION_NAME), когда встречает однозначные словесные конструкции. Находки автоматически получают REVIEW; ACCEPTED означает только подтверждение упоминания человеком, **не** подтверждение персонажа, факта, хронологии или канона. Очередь не делает сетевых вызовов, не пишет игровые кампании и не создаёт BookWorld. `gameplay_coverage=0`, `can_publish_bookworld=false` всегда.

## Тесты/границы
`apps/story_reader/test/book_source_analysis_test.dart`: детерминизм, provenance, checkpoint roundtrip, resume прерванной работы, review, подмена данных, wrong edition, retry/limit. Новые проверки должны пройти Flutter analyze/test в GitHub Actions до объявления PASS. Физический Android/Windows E2E не проводился. Состояние пока не подключено к UI и сохраняется только через encode/decode API; production durable storage ещё нет.

## Следующее
M2b2: durable приватные checkpoints в каталоге приложения, UI прогресс+review в **существующем** экране подготовки книги, сохранение после каждого батча, отмена/возобновление без потери статуса; далее извлечение фактов/событий/таймлайна, cross-chapter entity resolution, spoiler gate и human review. Не строить играбельный `.bworld` на основании regex-находок.
