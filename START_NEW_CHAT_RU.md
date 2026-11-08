# AI Story RPG — общий сюжет и NPC-диалоги

8 ноября 2026. Репозиторий shonentez-afk/AI-Story-RPG, ветка `feature/p0-bookwide-gameplay-readiness-20261107`, существующий [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) Draft. Не создавать микро-PR, второй движок/библиотеку и не менять main. E6d, tools/rpg_author и pinned contracts отложены пользователем. Очистка завершена — не повторять. Runtime прежний: автономный story_core/rich-v3/SQLite.

## Начать со статуса exact-head CI

**Новый код `4cbca1a54621ee0958c3fffbf62d6ed2be0cbbed`.** [CI #986](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773798), [M0 #1071](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773686). На момент записи Python, Dart и Flutter static analysis SUCCESS, M0 SUCCESS. Flutter test job **128600235711** ещё выполняется; M1.7 job **128600235739** ещё выполняет проверки импортёра/SQLite. Итог новых девяти тестов, всего Flutter и Windows/Android НЕ объявлен успешным. Следующий шаг — проверить именно эти jobs/HEAD, а не повторно внедрять код. Docs-only `[skip ci]` поверх 4cbca1a5 не заменяет тестируемый SHA.

Предыдущий [CI #985](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42434812662) на 80cdeb7f завершился FAILURE: 701 Flutter PASS / 2 SKIP / 2 FAIL. Исправления включены в 4cbca1a5: альтернативный тест теперь выполняет обязательный `act_N_end_alternative` и проверяет промежуточную сцену; негативный тест создаёт вложенную структуру через decoded JSON, поэтому List effects действительно попадает в parser вместо ранней ошибки Map<String,String>. Runtime и parser не ослаблены.

Последняя полностью принятая база до общего сценария — 1ac39320 / CI #982. Исправление прежней защиты ручной записи 5d33b2c прошло Flutter #984, но весь run был отменён новым push. [External RPG author #275](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773698) — отдельный отложенный E6d workflow, не подгонять его контракт и не называть все workflows зелёными.

## Что уже в коде

`ReviewedStoryNarrative` переносит принятую цель/конфликт/мотивы из UnifiedBookStoryPanel в тот же MultiActStoryPlanDraft и прежний общий редактор. Он делегирует неизменённые игровые правила, а не исполняет свободный текст. Панель связывает narrative с точной saved record hash и карточками; verifier не захватывает Flutter State и не передаётся через worker.

`NpcWritingCatalog` включает narrative.reviewDigest в digest и адрес черновика. Мотивы могут измениться при тех же mechanics, но новое согласие и отдельная редакция всё равно обязательны. Старый ручной текст сохраняется. Per-act путь без narrative сохраняет прежние ключи и payload shape.

`NpcWritingRequest` показывает и передаёт общую цель/конфликт как авторский замысел, назначение первого/ответного акта, условные связи и только мотив конкретного собеседника с разрешёнными source refs. Исход по условию обозначен UNKNOWN, не уже совершённым обещанием. Если основание мотива лежит позже первой сцены в тексте, весь мотив удерживается. Порядок текста не выдан за время мира, мотив не создаёт знания NPC.

Старый ZaiNpcCampaignWriting автоматически проверяет story checkpoint перед POST/каждым retry, после ответа и внутри lock перед записью — вместе с прежним author guard для героя/предметов/реплик. Итоговый NPC-review дополнительно связан с story digest; до/после worker проверяется живая история. Строгому v3 writer передаются прежние JSON и writer digest; схема .bworld не менялась. Изменение модели не может задавать effects.

## Проверки и границы

Девять новых тестов unified_story_npc_writing_test.dart: exact shown context, изоляция мотивов/будущих оснований, legacy addresses, согласие/guard, смена истории при 429 и late response, отозванные карточки, ручные строки и запрет model effects, phone consent, общая реальная компиляция с narrative+inventory → retry/resume → human review → ключ/два NPC/финал → SQLite restart/stateHash. Имеются два исправленных прежних теста #985. **Наличие тестов не равно их PASS**; CI ещё проверить.

Источник и API synthetic; Dart/Flutter в среде чата недоступны, локальный PASS/живой GLM не заявлены. Авторские мотивы не сертифицированы как литературная истина, нет общей гарантии отсутствия смысловых спойлеров или противоречий. Многофайловая межпроцессная транзакция не обещается, отправленный запрос не отзывается.

Остаются CANON, произвольная художественная структура вне agreement/exchange/disclosure, текст всех сцен, две реальные приватные русские FB2 с живым GLM и физический Windows/Android QA. #118 и Draft PR не закрывать по синтетике. Следующий результат после приёмки пакета — цельное содержательное прохождение реальной книги, а не новая мелкая подсистема.

[Статус](docs/CURRENT_STATUS_RU.md) · [Контракт и тесты пакета](docs/P0_STORY_GUIDED_NPC_FLOW_RU.md) · [Первый общий сценарий](docs/P0_UNIFIED_BOOK_STORY_RU.md)
