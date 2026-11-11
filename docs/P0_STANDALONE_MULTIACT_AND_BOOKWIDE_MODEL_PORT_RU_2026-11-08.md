# AI Story RPG — крупный перенос multi-act, NPC и полного анализа книги в автономный Dart

**8 ноября 2026.** Ветка `feature/p0-bookwide-gameplay-readiness-20261107`; существующий [Draft PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133). **Точный кодовый SHA `3c1a7aa19853d5ea13a031db4dc2ad06b80b2b96`.** Работы не разбивались на отдельные PR, изменения `main` и внешнего E6d не проводились. [Проект единого пути «книга → RPG»](DESIGN_UNIFIED_BOOK_TO_RPG_PATH_AND_AUTONOMOUS_AUTHORING_RU_2026-11-08.md) остаётся единой спецификацией, прежде чем переделывать мастер Flutter.

## Что выполнено в коде одним функциональным пакетом

**1. Перенесено НАСТОЯЩЕЕ многоактовое авторство без дублирования.** `MultiActTrialCompiler`, `StoryPlanTrialCompiler`, `BookwideNpcCampaignAuthoring`, `BookwideCampaignContract`, `BookwideNpcArc`, `UnifiedBookStoryDraft`, `ReviewedStoryNarrative`, `ReviewedHeroRole` и `ReviewedHeroSourceAction` теперь исполняются в `packages/story_authoring/lib/src`. Перенесены проверки связности актов и достижимых решений (`BranchContinuityAuditor`, `CrossActConsequenceGate`, `SourceBoundBridgeAuditor`, `SourceWorldTimeAuditor`, `CompiledCampaignCausalGate`). Flutter использует исходные публичные имена классов через **тонкие export-фасады**. Не создано альтернативного `StoryWorld`.

**2. Проверка литературных и повествовательных данных вынесена из облачных сервисов.** `WholeStoryLiteraryReviewManifest`, окна, finding/report, источник доказательств, summary, bounded repair / unchanged approval, `ReviewedProseSceneOverlay`, source-locked prose context/draft — pure Dart. `ZaiWholeStoryLiteraryCritic` и `ZaiSourceLockedProsePreviewService` остаются только адаптерами HTTPS/ключей/повторов. Действующие `glm-4.7-flash` и `maxAttempts=3` сохранены в проверяемом протоколе, чтобы переезд не подменял согласия. Ни одно ИИ-замечание не доказывает CANON или автоматическую правку игрового состояния.

**3. Отделён от приложения ПОЛНЫЙ проход анализа книги.** Чистые `SourceSemanticWindowPlanner`, `ZaiWindowReviewQueue`, `SemanticPreviewWireContract`, `ZaiWholeBookConsentManifest`, `ZaiWholeBookEventOutline` и `PortableWholeBookAnalyzer` находятся в `story_authoring`. Последний получает **колбэк модели** (local, cloud или тест), чтение/запись checkpoint и явное согласие на exact-digest всего набора окон. На каждом окне валидирует IDs/UTF-16/источник, атомарность учитывает через success-first write, позволяет Resume и отмену. Старый `ZaiAutoWholeBookAnalysis` в приложении теперь только клиентский адаптер к имеющемуся `ZaiSemanticPreviewService` и файловому репозиторию. Никакого запуска сети или доступа к файлам Android/Windows из package не происходит.

**4. Сохранена автономная сборка игрового архива.** Из предыдущего пакета `PortableReviewedDraftCompiler`, `BookAuthoringEngine` и нативные `compileReviewed*BookworldInWorker` на Dart `Isolate.run` по-прежнему доступны из CLI без Flutter. Используют существующий rich-v3 импортёр, причинные правила NPC и точный fingerprint исходника. Это **проверенный по структуре частный мир**, не автоматически литературно достоверная адаптация всей книги.

## Доказательства и CI

- Предшествующий baseline [CI #42452212594](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212594) и M0 #42452212571 — SUCCESS для предыдущего кодового SHA `df592c9` (НЕ подтверждение нового кода).
- Exact code SHA `3c1a7aa`: [AI Story RPG CI #42455037055](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455037055), [M0 #42455036949](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455036949) — M0 SUCCESS; на момент составления отчёта Python и Dart scenario SUCCESS, Flutter static analyze SUCCESS, **M1.7 authoring и Flutter widget/Windows/Android ещё проходили и НЕ объявлены полным PASS**. Следующий чат обязан прочитать окончательный результат по точному run ID и исправить, если красный, а не считать pending за SUCCESS.
- Обязательный gate `tools/ci_check_engine_boundaries.py` запрещает зависимости Dart-кода от Flutter/приложения. `packages/story_authoring/test/pure_multi_act_surface_test.dart` проверяет независимый импорт multi-act/NPC/literary типов. `portable_whole_book_analyzer_test.dart` проверяет явное согласие, все части исходника, Resume, неверного провайдера, испорченный checkpoint и отмену. Остались существующие Flutter integration, SQLite replay и ZIP/Python parity проверки.
- External RPG author tests на E6d по-прежнему FAIL; **его код/контракт не менять**, отдельный чат и отдельное согласование.

## Важные границы честности

- **Автономный runtime:** да, проверенный `.bworld` исполняется без Flutter/сети; `story_core` не зависит от приложения.
- **Автономный авторский Dart:** исходник/индекс, большая часть извлечения гипотез, model-independent bookwide windows, персонажи, сюжет, причинность, литература, ручная/проверенная сборка и CLI без Flutter. Облачный API — заменяемый внешний адаптер; self-hosted/local model может реализовать тот же порт.
- **«Передал роман → сразу готовая CANON RPG»: НЕТ.** Смысл, мотивы, персонажная память, длинный роман, полные 0/1/2 NPC по всем главам, реалистичность альтернатив и пользовательское согласие ещё требуют одобренного автоматизированного цикла. Private rich-v3 пока ограничен 192 сценами и не допускает полноценный private CANON/role-specific initial knowledge/time. Нельзя снять лимиты без строгого контрактного и причинного тестирования.
- **UI не «доведён»**: игровой экран, Герой/Предметы/Журнал/NPC, портреты/пузырьки диалога, spoiler-safe, 280dp и 200% text, полный единый мастер пока открыты. Не заявлять, что реальные кадры экрана проверены.

## Продолжение — ДВА больших пакета и один gate, никаких микро-PR

**Оставшаяся большая движковая работа:** завершить контракты полноценной книги — CANON/ALTER_FATE, role initial knowledge/inventory, book-wide act/scene coverage и снятие лимитов 48/192 с batch-fail-closed, литература/события/причинность, NPC и AI-reviewed prose. Никаких «исправлений 192» без согласованного формата v4/совместимой миграции и replay.

**Единый UI пакет после согласования движкового контракта:** один вход из библиотеки и one-session Resume, проверяемые экраны сюжета, игрок/предметы/журнал/диалоги/NPC, безопасный AI consent/Stop, 0/1/2 NPC, настройки/адаптивность/backup.

**Одно сквозное испытание:** две настоящие RU FB2, длинная книга, источник/цитаты, multi-act, сюжетная причинность, 0/1/2 NPC, несанкционированные знания/предметы, долгий Z.ai/429/offline local model, CLI ↔ Flutter byte/source parity, Windows/Android screenshots, SQLite save/fork/.bwsave, точный CI SHA. Сохранять PR #133 как Draft до проверки.
