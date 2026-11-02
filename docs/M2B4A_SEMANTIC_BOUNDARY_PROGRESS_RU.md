# M2b4a — семантический provider boundary: начальная реализация

Дата: 2026-11-02. Рабочая ветка: `feature/m2b4a-semantic-provider-boundary-20261102`.

## Реализовано в коде (ожидает CI)
- `source_semantic_provider.dart`: независимые `SourceSemanticProvider`, `SemanticExtractionRequest`, `SemanticCandidate`, `SemanticCandidateBatch` и обязательный `SemanticProviderGate`.
- Реальный `OfflineRuleProvider` использует только принятые M2b1 регулярные выражения через read-only `SourceAnalysisSession.scanChunk`. Это локальные **предположения**, не семантическое понимание, сюжет или NPC.
- Отсутствующая локальная модель явно недоступна; облачный провайдер недоступен и запрет cloud enforced до вызова `extract`. Даже инъекция нового cloud-провайдера в gate не запускает сеть.
- Валидатор отклоняет несуществующие chunk ID, чужую редакцию, изменённые цитаты и SHA, некорректные UTF-16 границы, дубликаты, неподходящие категории, `CONFIRMED`, неожиданные spoiler gates и фальшивый `can_publish_bookworld`.
- Лимиты запроса: 12 chunks/64 KiB текста. Ответ: 360 кандидатов/256 KiB, цитаты 180 UTF-16. По умолчанию `gameplayCoverage=0` и `canPublishBookworld=false`.
- `source_semantic_provider_test.dart` содержит тесты позитивного локального пути и негативных payloads.

## Не готово и не заявляется готовым
- Контрольные точки/возобновление M2b4a; UI-страница/панель семантических кандидатов; реальные LocalModel и Cloud opt-in; полноценный `IntermediateStoryBlueprint`; конвертация пользовательской книги в RPG.
- Существующие M2b1/M2b3b/M2b3c checkpoint, SQLite кампании, книги, UX, `.bworld` и `.bwsave` не менялись.
- Ручные Windows/Android E2E, полные 10+ литературных контрольных случаев, длинные книги и accessibility ещё SKIP.

## QA
Статус: CODE ONLY / GitHub Actions CI PENDING. Для принятия нужен точный SHA, Dart/Flutter analyze и все тесты, Python/world, Windows и Android сборки. До этого PR не объединять.

## Дальше
M2b4a-2: приватные атомарные semantic checkpoints, корректное возобновление после отмены и смены модели, обязательные негативные тесты; затем встроенная (а не отдельная библиотека) UI-панель и только после этого проверяемый M2b4b.
