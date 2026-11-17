# AI Story RPG — полный аудит UI/UX всего приложения и автономности движка

Дата: 8 ноября 2026.
Ветка: feature/p0-bookwide-gameplay-readiness-20261107, PR #133 — OPEN / DRAFT.
Аудируемый код приложения: 6c3750bae27c30c5fdb67f17a055e6563e8081b0; CI #987 (42439491413) — COMPLETED / SUCCESS, включая Python, Dart, M1.7/ZIP/SQLite/standalone, Flutter analyze и widget, Windows portable, Android APK. M0 #1072 (42439491496) — SUCCESS. Последующие коммиты UX-аудита — документация, а не новые испытания.
Условия: не изменять main, не объединять PR, не затрагивать E6d, не повторять очистку Actions. Сначала аудит, затем согласованный единый пакет исправлений.

## 1. Метод проверки и степень доказательности

Инвентаризированы все 171 Dart-файл в apps/story_reader/lib, 132 файла Flutter-тестов, 4 отдельные пакета движка, пользовательские экраны/навигация, тестовые и CI контракты. Для более 50 UI-модулей проверены исходники, реальные входы/действия, подписи, состояние ожидания и ошибки, наличие согласия/отмены, возврат, зависимость от движка и тестовое покрытие. Критические экраны/settings/import/gameplay/backup изучены подробно. Это **сквозной статический и CI UX-аудит всей доступной функциональности**, НЕ пиксельный осмотр каждой комбинации темы/устройства и НЕ доказательство ручной работы интерфейса на Windows/Android. Нет physical GUI, живого GLM, скриншотов, TalkBack/Narrator и проверенного фонового режима Android.

Статусы:
- **PASS (CI)**: действующий happy/negative автотест подтверждает конкретное поведение; не утверждает ручной UX.
- **PARTIAL**: реализация существует и часть тестов проходит, но сценарий/масштаб/доступность не доказаны полностью.
- **RISK (source)**: проблема или явная уязвимость UX установлена по исходникам; до визуального утверждения необходим воспроизводимый тест.
- **NOT READY**: обязательная часть обещанного конечного результата отсутствует, не эквивалентна техническим тестам.

Главное решение: автономное ядро готово исполнять проверенные игры без приложения. Но **всё приложение и автоматическое превращение произвольной книги в литературную RPG к релизу 1.0 НЕ ГОТОВЫ**.

## 2. Обязательная архитектура: движок самостоятелен

Существующая корректная зависимость:
- packages/story_core — детерминированные правила, сцены, предметы, NPC, состояния и причинная проверка. **Нет Flutter, SQLite, файлов и Z.ai**; зависимости только Dart SDK/crypto.
- packages/story_runtime_adapter — соединение с story_engine, не владеет исходным состоянием.
- packages/bookworld_format — строгая проверка/переносимый игровой пакет .bworld. Может зависеть от вспомогательных сервисов формата, но не Flutter-приложения.
- packages/campaign_manager — SQLite журнал, save/reopen, .bwsave, не переписывает игровые правила; UI для него необязателен.
- apps/story_reader — один Flutter-клиент, импорт книги, visualizations, consent, authoring screens и адаптеры. При игре в .bworld API/ИИ не обязателен.

Автоматическая граница: tools/ci_check_engine_boundaries.py проверяет imports и pubspec всех 4 пакетов, запрещает engine→app и Flutter в story_core. Обязательный шаг в .github/workflows/android-ci.yml, затем standalone Dart CLI (packages/campaign_manager/example/standalone_rpg.dart) без Flutter и реальная SQLite replay. Все эти этапы в CI #987 SUCCESS. Отдельный репозиторий/новый движок сейчас не требуется.

**АРХ-P0-01 — слой подготовки книги ещё НЕ отделён от приложения.** Источники story_plan.dart, bookwide_storyplan_composer.dart, narrative_book_model.dart, source_evidence_graph.dart и многие другие алгоритмы подготовки/проверки находятся в apps/story_reader/lib. Некоторые составные компиляторы импортируют пакет Flutter напрямую: reviewed_gameplay_compiler.dart, whole_book_npc_campaign.dart, campaign_prose_authoring.dart, native_private_bookworld_compiler.dart. CI архитектуры проверяет только уже вынесенные 4 пакета и не доказывает автономность полного pipeline FB2→Game. **Требование:** не переносить UI во внутрь story_core; чистую авторскую/сценарную логику и модели по мере исправлений переиспользовать через Dart-контракт без Flutter, сеть/файлы/compute вынести в адаптеры. В перспективе отдельный CLI-клиент должен суметь собрать/проверить подготовленную игру без импорта Flutter. Это отдельная архитектурная приёмка, не переписывание существующего движка и не работа с отложенным внешним E6d.

## 3. Полный реестр пользовательских экранов и функций

### 3.1. Запуск, библиотека, чтение, настройки

| Экран/контроллер/функция | Что проверено | Итог |
| --- | --- | --- |
| AIStoryApp, HomePage | системная/светлая/тёмная тема, старт/Continue по свежему сейву, пустое состояние, библиотека, демо, кампании, настройки | PASS CI / PARTIAL при ошибках настроек |
| LibraryPage, BookStorage | единый импорт TXT/FB2/FB2.ZIP/.bworld, название/обложка/поиск/сортировка, незагружаемый файл, прямые Читать/Играть/Подготовить, удалить | PASS по существующим widget/FS; P1 приватность удалённых черновиков |
| BookImporter, BookTextDecoder | UTF-8/UTF-16/Windows-1251, FB2 изображения, повреждённый файл, FB2.ZIP, 20 MiB cap, worker isolate | PASS по тестам; EPUB НЕ заявлен |
| BookReaderPage | открытие FB2, оглавление/переключение глав, обложка, изображение/zoom, закладки, позиция чтения, большая глава/виртуализация, возврат | PASS CI; P2 bookmarks по главе |
| BookReadingStore | semantic paragraph anchor + pixel legacy fallback, при reflow/ориентации сохраняет смысловое положение | PASS CI; **не повторять устаревший баг «только пиксели»** |
| ReadingSettingsSheet/ReadingSettingsStore | 4 палитры, размер шрифта 12–32, высота 1.2–2.2, поля 12–48, «Готово», цепочка записи | PASS happy path; P1 обработка ошибок записи |
| ReaderChromeButton/ReaderChromeKeyboard | обычный/читательский/без панелей, F11/Escape, временный показ управления | PASS widget; P2 «Полный экран» — скрытие chrome, не native OS fullscreen |
| SettingsPage, AppTheme/AppAppearanceController | системная/светлая/тёмная тема окон, чтение и сброс, ссылки на ИИ/библиотеку/сейвы/приватность, версия | PARTIAL; P1 persistence failure, тексты, управление данными |
| AiConnectionSettingsPage | Standard API key, secure vault, согласие на подключение, запрос-проверка, удаление ключа, ошибок 401/403/429, 320dp/200% | PASS CI по действующим путям; P1 вводящие в заблуждение описания и live-provider не проверен |

### 3.2. Игра и данные, от демо до BookWorld

| Экран/функция | Проверено | Итог |
| --- | --- | --- |
| StoryReaderPage, makePilotStory | встроенная демо-история, реальные варианты и эффекты, автосохранение, ручное сохранение, продолжение/сброс | PASS CI; legacy pilot отличается от полноценного BookWorld |
| CampaignsPage | общий список пилотных и BookWorld прохождений, поиск актуального, .bwsave v1/v2, fork, экспорт, удаление/ошибки | PASS CI; legacy удаление без обязательного backup требует ясного предупреждения |
| WorldCampaignsPage | карточка мира, новое прохождение, fork, импорт/экспорт .bwsave, удаление, состояния loading/retry | PASS CI; физический системный диалог не проверен |
| WorldBackupActions | перед удалением BookWorld/кампании нужно сохранить .bworld/.bwsave; запрет удаления мира с кампаниями и revision guard | PASS unit/widget; реальный roundtrip внешнего файла на устройстве не проверен |
| WorldSaveImportFlow | preview и согласие, строгий импорт/replay до вставки нового сохранения, соответствие world hash | PASS CI |
| WorldPlayPage | офлайн сцены, блокировка решения, динамический журнал, настройки чтения и fullscreen, 35+ SQLite ходов/reopen | PASS CI; P1 смешанные темы и тихая ошибка читательских настроек |
| GameInfoSheet/GameQuickBar | Герой/Предметы/Журнал; NPC только при подтверждённой встрече, реальные item owners/memory | PASS основной поток; P1 ширина 4 кнопок при узком viewport |
| DialogueStage | последовательные реплики, имя, локальный портрет, история реплик, пропуск, переход к решениям, сохранение позиции | PASS widget; доступность/цвета кнопок при независимых палитрах не полностью проверены |
| LocalDialoguePortraitStore | только локальный PNG ≤2 MiB, hash/pixel size, ошибки подмены, привязка к кампании | PASS unit; при переносе .bwsave портреты не переносятся, UI объясняет |
| FreeTextActionPanel | свободный ввод, локальное сопоставление с доступным действием или опциональная AI-подсказка, отдельное согласие и подтверждение настоящего хода | PASS тестами; не свободный AI-движок, а выбор из разрешённых движком действий |
| WorldLibraryGateway | isolate/SQLite, строгая установка/загрузка/удаление и запрет фальшивого хода, защита редакции | PASS контрактами/CI; не заменять интерфейсом |

### 3.3. Подготовка исходной книги, источник и литературная проверка

| Экран/функция | Проверено | Итог |
| --- | --- | --- |
| BookRpgStartPage | раздельные короткий offline и AI-путь с пояснением, no-POST при открытии | PASS widget; P1 несоответствие описания позднего выбора героя |
| SourceIndexPreviewPage | офлайн индекс, поиск имён/событий, скрытие спойлеров, подтверждение цитат, шаги/расширенная подготовка | PASS частично; P1 два конкурирующих входа и большой экран |
| ZaiWholeBookAnalysisPage | число окон/цитат, показ отправки, отмена, локальные checkpoints, повтор ошибок, переход к плану | PASS mock; live GLM/background не проверены |
| SourceSemanticReviewPanel | локальные кандидатные утверждения/порции/стоп/сброс, ошибки checkpoint | PARTIAL: исходники и целевые тесты, не ручной UX |
| SourceNarrativeReviewPanel | проверка цитат/фактов, показ следующих, восстановление/сброс | PARTIAL |
| SourceRelationsReviewPanel | связь персонажей, идентичность, хронология, пагинация и сброс | PARTIAL |
| SourceCharacterDossierPanel | карточки, поиск/пагинация, спойлеры, обновление | PARTIAL |
| SourceEditorialReviewPage | персонажи/события/хронология, фильтры, исходная проверка и переход к NPC | PARTIAL |
| ZaiSemanticPreviewPage | точное содержимое облака, титул отдельно, подтверждение/отмена, возвращение | PARTIAL |
| ZaiCrossWindowReviewPage | алиасы, подтверждение пересечений, противоречия, контроль сброса | PARTIAL |
| ZaiEditorialConsistencyPage | спорные утверждения, согласие, отзыв, цитаты, список проверок | PARTIAL |
| ZaiManualSourceAlignmentPage | привязка вручную, раскрытие спойлеров, отзыв и scoped reset | PARTIAL |
| ZaiSourceSceneWorkbenchPage | source-locked черновые сцены, ручные правки и спойлеры | PARTIAL |
| ZaiCausalChoicesPage | альтернативы, source-bound правила, предупреждения и подтверждения | PARTIAL |
| ZaiPrivateCompilationPage | частная сборка, проверка и отказ от повреждённой редакции | PARTIAL |

### 3.4. Конструкторы, сюжет, герой, NPC, предметы и проза

| Экран/функция | Проверено | Итог |
| --- | --- | --- |
| QuickRpgFromBookPage / QuickRpgPage | короткая offline RPG и выбор «сохранить/менять» сюжет, локальное подтверждение | PASS CI; НЕ полноценный CANON |
| ReviewedStoryEditorPage | источник, private-use, редактирование и сборка | PARTIAL |
| MultiSceneEditorPage / DraftSceneGraphPanel | ситуации, выборы, условия, граф сцен, проверка ошибок, удаление | PARTIAL; длинные формы требуют device QA |
| BookActDraftPage | пакеты актов, сохранённые части, остановка, общий сценарий через AppBar иконку | PASS target, P1 скрыта основная функция |
| UnifiedBookStoryPanel | единая цель, мотивы, строгий source/role digest, облачное согласие и принятие | PASS CI только в поддержанных лимитах; NOT READY для больших/несовместимых книг |
| MultiActTrialPage / MultiActTrialPage editor | частная пробная игра, герой, межактовые связи, предметы, NPC, source encounters | PARTIAL, проход к полному редактору скрыт через overlay icon |
| WholeBookNpcCampaignPage | постоянный герой, выбранные проверенные NPC, предметные последствия, диалоги, restart/consent/установка | PASS positive, **P0 без подходящего NPC путь блокируется** |
| NpcEditorialPage | сохранение карточки, алиасов, заметок и постоянного NPC ID | PARTIAL |
| NpcKnowledgeRulesPage | правила знания, памяти, предметов и life-state, source-locked проверки | PARTIAL, 1815 строк одного UI, тяжёлый ручной поток |
| NpcDialogueDraftPage | AI-черновик разговора по отдельному согласию, перенос в редактор | PARTIAL |
| NpcDialogueResponsesReviewPage | ответы героя по подписанным choice ID, просмотр последствий и пропуск | PASS target |
| NpcContinuityPanel | связи NPC, нарушения, списки кандидатов и исправления | PARTIAL |
| SourceLockedGameplayReviewPage / WholePlanGameplayBatchPage | предметы, знания, выборы, целостность разрешений по сценарному SHA | PASS tests/CI для проверенных вариантов |
| SourceLockedProsePreviewPage / SourceLockedProseBatchPage | один/несколько художественных абзацев, сохранение, отказ/отмена, отдельное согласие | PARTIAL |
| SourceLockedProseAuditPage / WholeStoryLiteraryReviewPage | литературная критика/model suggestions, реальные цитаты, последовательные approvals | PASS контракт/черновики; истинность сюжета вручную не подтверждена |
| CampaignProsePage | все сцены и развязки, manual/AI, resumable save, отдельное согласие, strict writer | PASS CI #987; P1 техническое тело сцены ещё не очищено |
| PrivateGameReadinessPanel / PreparationEditorHelp | ранняя проверка архива, помощь/пояснения, переход к установленной игре | PARTIAL; не единый общий readiness всей книги |

Все перечисленные модули просмотрены по исходным UI-веткам и сопоставлены с релевантными тестами. PARTIAL НЕ означает доказанный баг; означает, что widget/contract QA недостаточен для заявления о полном ручном UX.

## 4. Подтверждённые недостатки и воспроизводимые риски

### Критические: продуктовый путь книга→игра

**UX-P0-01 — общий поток требует NPC.** WholeBookNpcCampaignPage после базовой компиляции отказывает, если BookwideNpcCampaignAuthoring.discover не дал кандидата («Нужны другие подтверждённые NPC ...»). Финальная проверка требует непустой _edits. Автономный story_core умеет кампании без NPC. Необходимо сохранить единый путь «собрать без NPC», не отключая строгие NPC-контракты, когда NPC есть. Приёмка 0/1/2 NPC, plain prose, независимый импорт, SQLite.

**UX-P0-02 — сложная книга обнаруживает ограничения слишком поздно.** UnifiedBookStoryContext.create требует полностью проиндексированный исходник, 2–12 актов, ≥2 исходных события в каждом, 0 пропущенных глав, ≤15 ролей, JSON ≤160 KiB; BookwideSourceEncounters ограничен 24 дополнительными событиями на акт и 192 сценами. Эти ограничения правильно предотвращают молчаливую потерю, но их нельзя выдавать за поддержку произвольного романа. До нового POST нужен общий явный preflight с «что исправить», пунктами «пропущенные события/персонажи/ёмкость», и масштабируемая многооконная обработка в рамках одного режима.

**UX-P0-03 — настоящее CANON и подтверждённая литературная причинность отсутствуют.** У unified accepted draft isFullBookRpg=false, hasConfirmedLiteraryMeaning/WorldChronology/ActorKnowledge/SourceProvenCausalBridges=false; выбранный тип PRIVATE_ALTER_FATE_PROPOSAL. Две художественные концовки != исходный финал текста. Не выдавать «Сохранить сюжет» короткой пробы за полноценно подтверждённый CANON.

**UX-P0-04 — реальные книжные/платформенные acceptance gates.** Grimm 62 сказки (англ. public domain) в CI даёт реальный FB2/import/index/offline checkpoint, не полноценный богатый игровой сценарий. Частный RU Andersen FB2 тест в публичном CI SKIP и тоже не доходит до игры. Отсутствует проверенный на устройстве цикл две разные русские FB2 → живой GLM → исходные карточки → NPC/предметы → .bworld → разные концовки → .bwsave/SQLite/reopen. Никакого «готово для любой книги» до этой приёмки.

### P1: достоверность UI, настройки, сохранения и доступность

**UX-P1-01 — два конкурирующих маршрута и скрытые ключевые переходы.** LibraryPage одновременно показывает «Читать», «Играть по книге», «Подготовить к RPG»; «Играть» открывает BookRpgStartPage, «Подготовить» — SourceIndexPreviewPage со старым объяснением короткой пробы. В BookActDraftPage единый сюжет доступен только через IconButton в AppBar; MultiActTrialPage помещает переход к NPC в Positioned поверх другой страницы. Требуется один основной видимый мастер, короткий путь к Resume и расширенные редакторы как необязательные шаги.

**UX-P1-02 — ошибка сохранения темы скрыта.** AppAppearanceController.change изменяет value и notifyListeners ДО await SharedPreferences, не откатывает при исключении и не проверяет bool из setString/setBool. ChoiceChip вызывает async method без обработки результата. При failed storage пользователь видит выбранную тему как сохранённую; при двух быстрых изменениях нет очереди записи. Тесты app_theme_test проверяют только успешные настройки. Сделать serial persistence, catch/UI feedback, rollback или явное unsaved состояние, fault-injection tests.

**UX-P1-03 — читательские настройки: разные fail paths.** ReadingSettingsStore сериализует операции (хорошо), но результат bool из SharedPreferences.setInt/setDouble не проверяет. В WorldPlayPage._saveReading исключение поглощается без сообщения; BookReaderPage._change запускает save без catch. Это **по коду доказанная неполная обработка ошибки**, не утверждение, что повреждена реальная позиция книги. Нужны нефатальный retry/status, проверка write result, согласованный UI в читалке, пилоте, BookWorld и SettingsPage.

**UX-P1-04 — удаление книги не очищает отдельные данные подготовки.** LibraryPage._deleteBook вызывает только BookStorage.remove(bookId), удаляет файл из ai_story_library. SourceAnalysisCheckpointRepository и специализированные NPC/AI/prose/editorial stores держат множество отдельных scoped files по fingerprint в application support. При удалении первичного FB2 **нет каскадного удаления/показа связанных черновиков**. Они могут содержать авторские заметки, утверждения и предложенные реплики. В настройках нет «управления сохранёнными черновиками/объёмом/приватными данными». Нужен preview последствий и раздельные действия: только книга / черновики конкретной редакции / созданные миры и сохранения. Не удалять последние автоматически.

**UX-P1-05 — риск низкого контраста при независимой теме окон и страниц.** WorldPlayPage красит фон палитрой ReadingPreferences (вплоть до белого), но ExpansionTile «Свободное действие» и FreeTextActionPanel используют обычный Theme.of(context) и нестилизованные Text/TextButton/ListTile поверх transparent Material. Сочетания dark app+light/sepiа reader и наоборот могут дать слабый контраст/невидимые подписи. DialogueStage задаёт правильный контраст своим текстам, но его кнопки местами используют app Theme. Сейчас контрастные тесты измеряют основной readerText, НЕ все controls при всех 3×4 комбинациях. Исправить через локальный Theme/ColorScheme для reading surface и измерить подписи, hint, focus, disabled, errors в widget/golden.

**UX-P1-06 — нижняя панель с NPC при узком доступном viewport.** GameQuickBar: 4 Expanded children, каждый ConstrainedBox(minWidth:72), общие horizontal padding 12+12; для четырёх элементов требуется ≥312 logical pixels доступной ширины. Тест «узкий телефон» использует 320dp и не покрывает <312dp после safe-area/insets/крупного шрифта. Нужен adaptive bar/overflow, TalkBack/Narrator hit zones и тест 280/300dp + 200%.

**UX-P1-07 — тексты настроек ИИ не отражают нынешние возможности.** AiConnectionSettingsPage описывает лишь «ручной предпросмотр по одному фрагменту», «полная адаптация и игровой ИИ ещё не подключены», хотя внутри есть full-window analysis, unified story, AI NPC/prose и добровольный per-turn AI advisor (он лишь предлагает допустимый ход). «Разрешить проверочное соединение» используется как глобальное разрешение подключения API для других независимых согласий; нужно яснее обозначить сервис vs конкретную отправку и показать статус ключа/бюджета уже при входе в подготовку. Не заявлять текущий тариф «бесплатный» без проверки у провайдера.

**UX-P1-08 — сохранение/экспорт на устройстве не проверены физически.** WorldBackupActions отклоняет удаление при отмене saveFile, проверяет revision и повторяет strict SQLite checks — хорошо. Однако результат FilePicker.saveFile(path != null) не подтверждён независимым чтением созданного файла на физическом Windows/Android; UI пишет «копия сохранена». Нужен device roundtrip: реальные external documents providers, доступ к папке, отмена, перезапуск, перенос .bworld+.bwsave на второй девайс. Это недоказанный риск, а не установленная потеря данных.

**UX-P1-09 — новые длинные редакторы и статусы не имеют полной UX-приёмки.** SourceIndexPreviewPage 1183 строк UI, MultiActTrialEditor 1253, NpcKnowledgeRulesPage 1815; CampaignProsePage строит список по всем сценам, потенциально до 192, без полноценной ленивой пагинации. Отдельные окна согласий, reset и loaded revision уже есть, но общее «готов/ожидает/не хватает/как исправить», устойчивый возврат и минимальная прокрутка отсутствуют. Подтверждать usability нужно 320/360/600dp, keyboard/focus, 200% fonts, Android back/resume.

**UX-P1-10 — финальная подача остаётся технической.** ReviewedCampaignProseWriter добавляет текст повествования ПЕРЕД исходным текстом сцены, не заменяет служебные поля и встроенные пометки. Автоматические проверки охраняют правила, но не гарантируют литературную чистоту показанной страницы. Делать presentation-only очистку с сохранением source/provenance, NPC turns и условий выбора.

**UX-P1-11 — отклонения при старте/настройках без recovery.** AIStoryApp.initState вызывает AppAppearanceController.instance.load() без error handler и fallback UI при неисправных prefs; для первого кадра остаётся light-theme по умолчанию, но ошибку настройки пользователь не видит. Проверить отказ SharedPreferences и повторный вход; не трогать игровые данные при ошибке темы.

### P2: качество, формулировки, эргономика

**UX-P2-01:** Кнопка «закладка» в читалке сейчас запоминает номер главы (List<int> bookmarks); текущая позиция внутри главы сохранена семантическим anchor, но несколько точных пользовательских закладок внутри длинной главы отсутствуют. Не путать две функции.
**UX-P2-02:** «Шрифт» в тексте сброса — фактически только размер; семейство/начертание шрифта пользователь не выбирает. Объяснить честно или добавить позже.
**UX-P2-03:** FilePicker для портрета предлагает любой image, но локальное хранилище принимает строгий PNG; предупреждать о PNG до выбора или предлагать безопасную локальную конвертацию.
**UX-P2-04:** Кнопка «Полный экран» меняет chrome Flutter и не переключает native OS display fullscreen; подпись и справку уточнить.
**UX-P2-05:** В ряде редакторов показаны внутренние source_event_id/act_id, SHA и технические детали. Убрать из основного повествовательного потока, оставить в раскрываемом «Диагностика».
**UX-P2-06:** EPUB ещё не импортируется (поддержаны TXT/FB2/FB2.ZIP). Не рекламировать EPUB до реального парсера, пройденного реального файла и правовой проверки.
**UX-P2-07:** Некоторые объяснения в старой расширенной подготовке по-прежнему называют возможной только короткую RPG; технически это верно для гарантированной литературной полноты, но не объясняет уже существующий экспериментальный unified путь. Вычистить противоречия без обещания готового CANON.

## 5. Подробный чек-лист раздела «Настройки»

| Настройка / действие | Наличие и проверка | Проблема / действие |
| --- | --- | --- |
| App theme: system/light/dark | есть, widget checks, старый dark key migration | ошибка/гонка записи не обработана; тест storage failure |
| Reading palette: light/sepia/dark/OLED | есть, 7:1 контраст основного текста в тестах | проверить ВСЕ дочерние controls в 3×4 сочетаниях, а не только body |
| Font size | 12–32, общий sheet для читалки и игры | save failure; семейство шрифта отсутствует (не выдавать за настройку) |
| Line spacing | 1.2–2.2, сохраняется | проверить rapid drag/failure/reset на устройствах |
| Horizontal margins | 12–48, сохраняется | узкие устройства, 200%, изображения/диалоговые карточки |
| Reading settings reset | отдельное подтверждение; книги/сейвы не трогает | сброс на живых открытых страницах / failure UI ещё не доказан |
| Reader chrome/fullscreen | F11/Esc, меню режимов, показ контролов | проверить keyboard focus, TalkBack, системные жесты и физический fullscreen |
| API key Z.ai | FlutterSecureStorage, очистка поля после успешной записи | неправильный секрет не выводить, OS vault failure recovery |
| Global cloud service permission | default off, явный opt-in, cancel/remove | отделить «разрешено подключение» от «что конкретно передать» |
| Test connection | отдельная ручная кнопка и ответ GLM | live network/429/401/offline/device нет |
| Book analysis permission | точные цитаты, до запроса отдельно разрешить | показать реальный общий бюджет/количество по этапам |
| Saved books/campaign links | работают | нет единого управления черновиками, объёмом данных/чисткой |
| Privacy/deletion | текст объяснения локальности и согласий | книга удаляется без предложенного контроля authoring checkpoints |
| Version/app info | 0.1.0 preliminary, соответствует pubspec 0.1.0+1 | рядом показать формат/сборку при bug report, без лишних диагностических экранов |
| Accessibility | Material Semantics для части кнопок | 200% не везде, TalkBack/Narrator/high contrast/keyboard focus device QA не пройден |

## 6. Автотесты, покрытие и пробелы

CI #987 SUCCESS подтверждает существующие Python/Dart/schema/SQLite/Flutter и платформенные сборки. Есть целевые тесты: app_theme_test (5), reading_preferences_test (4), reading_settings_close_test (1), ai_connection_settings_page_test (2), ai_connection_test (4), book_reader_ux_test (6), book_reading_state_test (5), settings_library_responsive_audit_test (2), scene_dialogue_stage_test (6), world_integration_test (22), game_panels_test (9), world_npc_relationship_panel_test (3), book_open_encoding_audit_test (5), book_open_library_audit_test (5), campaign_prose_flow_test (11), unified_story_npc_writing_test (9), плюс множество редакторских suites.

**Чего эти тесты НЕ доказывают:**
- 3 темы окон × 4 reading palettes × размеры 280/320/360/600dp × text scaling 100/200%, включая ошибки и disabled-контролы.
- Accessibility screenreader order, keyboard traversal/shortcuts, чтение названий и кнопок в каждом длинном редакторе, отсутствие потери фокуса после диалога.
- Сбой native Preferences / secure vault / FilePicker, повтор после удаления/переноса/рестарта приложения, фактическое чтение внешней резервной копии.
- Android background/suspend/rotation, возврат приложения на экран подготовки, длительные AI-проходы с реальными 429/connection-loss.
- Две структурно разные приватные русские FB2 со смысловой приёмкой; full English Grimm fixture подтверждает импорт, не полноценную игру по всему сборнику.
- Пользовательский тест без подсказок: найти полный сценарий, выбрать подтверждённого героя, понять согласия, вернуться после ошибки, пройти альтернативную ветку и экспортировать сохранение.

### Обязательная матрица регрессий после связанных исправлений

1. **Первый запуск**: тема, новая пустая библиотека, импорт и исключения, переход в чтение/игру; второй запуск восстановит состояние.
2. **Читалка**: длина 20 MiB, FB2 изображения, оглавление, bookmarks, anchor после font-size/theme/resize/orientation, 4 палитры; ошибки prefs и reader-position.
3. **Библиотека/данные**: поиск и сортировка при повреждённых файлах, отмена импорта, удалить книгу с предупреждением о черновиках, миры/сохранения не исчезают молча.
4. **Демо и BookWorld**: сохранение/восстановление, заблокированные варианты, диалог и пропуск, NPC/вещи/журнал, fullscreen, свободный ввод офлайн и с отдельно разрешённым ИИ.
5. **Экспорт/импорт**: .bworld / .bwsave v1/v2, снимок до удаления, system picker, повреждение и неизвестный мир, Android/Windows path и внешние документы, повторная проверка SQLite после reopen.
6. **Настройки**: system/light/dark, 4 палитры, sliders, reset, write failure/rollback, secure key save/delete, cloud toggle и отсутствие утечки исходной книги без согласия.
7. **Вся подготовка**: local source, 0/1/2 NPC, 1/12/>12 актов, отсутствующие цитаты/роли, offline-only, GLM 429, stop/restart, персонаж и мотивы, сюжет, инвентарь, подтверждение, prose и запуск.
8. **Устройства и визуальный контроль**: 280/320/360/600/desktop resize, 200%, high contrast, TalkBack/Narrator/keyboard, реальный Android/Windows, скриншоты каждого режима и проверка контраста.

## 7. Очерёдность реализации — без разрушения автономного движка

**Функциональный пакет A: «Все основные пользовательские пути и настройки».** Единый видимый вход в создание/продолжение RPG; ранний readiness и поправки к сообщениям; опциональный NPC и fallback в существующую кампанию. Одновременно исправить управление ошибками темы/чтения, privacy/data cleanup объяснения и контраст reading surface; проверить книгу/сейвы/режимы и несколько устройств в одних тестах. Не делать micro-PR на каждую строку UI.

**Функциональный пакет B: «Отделяемая подготовка и масштабируемая история».** Вынести чистые сценарные/литературные модели из apps/story_reader в reusable Dart-компоненты (не второй engine); оставить Flutter, file picker, OS vault и compute только в клиентских адаптерах. CLI contract и authoring-layer tests. Далее масштабирование полного сюжета, CANON и очищенный presentation layer.

**Пакет C: «Полный UX acceptance».** Проверяемый exact-head CI Python/Dart/SQLite/Flutter/Windows/Android + manual visual/keyboard/a11y/physical backup/restores + две реальные RU FB2 с live GLM и ручным литературным сравнением.

До выполнения P0 не считать AI Story RPG «готовой для любого FB2», не объединять #133 и не закрывать issue #118. Отложенный E6d не менять. Предыдущий аудит пути к игре: P0_FULL_ENGINE_UX_AND_BOOK_CREATION_READINESS_AUDIT_RU_2026-11-08.md. Следующий чат: START_NEW_CHAT_RU.md.
