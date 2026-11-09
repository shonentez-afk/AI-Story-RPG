# E6h — аудит основного AI Story RPG после принятия PR #124 (2026-11-06)

**Тип:** read-only аудит основного приложения + корректировка внешнего плана; это НЕ разработка Flutter, НЕ изменение основного `main`.  
**Срез live GitHub:** 2026-11-06 ~11:39 UTC (у пользователя локальное время около 18:39 UTC+7).  
**Сравнение:** `959c8134f4ef20cd00dd4039d8d131638f502f60` → **`6711011c0e55ca14f43c0ad0cab1f9976754c08a`**; ровно 27 новых коммитов, все в PR #124 и его слиянии. Main уже содержит более ранние PR #121, #122, #123.

## 1. Что реально внедрено

| PR/компонент | Подтверждено по commit/исходнику | Что это значит для E6 external author |
|---|---|---|
| [#121](https://github.com/shonentez-afk/AI-Story-RPG/pull/121) M2g3f.1 | Единый вход `BookRpgStartPage`: offline quick mode или полный анализ Z.ai, без скрытого вызова API | Не писать второй book-import GUI или второй мастер; внешний навык компилирует игру в поддерживаемый импортёр |
| [#122](https://github.com/shonentez-afk/AI-Story-RPG/pull/122) M2g3f.2a | Resumable act preparation и per-POST user consent с сохранением checkpoint; адаптивно разделяет одно-главные тексты с ≥4 событиями | Переиспользовать архитектурные semantics прогресса/identity/SHA; не повторять одно и то же в двух несовместимых форматах |
| [#123](https://github.com/shonentez-afk/AI-Story-RPG/pull/123) M2g3f.2b.1 | Вариант `WholeStoryLiteraryUnchangedApproval` позволяет после полной независимой рецензии и двух подтверждений компилировать **неизменённый** план в private rich v3; g2 путь сохраняется | E6 должен иметь общий литературный quality gate; не принимать «не было замечаний» как доказательство отсутствия пропущенных событий |
| [#124](https://github.com/shonentez-afk/AI-Story-RPG/pull/124) M2g3f.2b.2 | `RichSceneDialogue` — deterministic parser; `RichPrivateBookworldWriter` записывает **опциональное** `source/provenance.json.presentation.scene_dialogues` с scene text SHA и turns; независимая проверка в Dart и Python; `WorldGameView` и `DialogueStage` проигрывают подписанные turns; legacy fallback | E6 должен готовить **атрибутированный текст** согласно фактическому parser. НЕ писать свой несовместимый второй формат для тех же v3-линий |

**Важный факт:** PR #124 уже **MERGED** и main HEAD `6711011c`, хотя первый абзац `docs/CURRENT_STATUS_RU.md` и `docs/M2G3F2B2...` всё ещё говорит «рабочая ветка». Это устаревшая строка внутри документа, а не статус ветки. Источник факта — live GitHub commit/PR/код.

## 2. Точные границы уже существующих структурированных реплик

`packages/bookworld_format/lib/rich_scene_dialogue.dart`:
- `RichDialogueTurn` = **`{speaker: string|null, text: string}`**. Это НЕ `world_actor_id`, `speaker_id`, `turn_id`, эмоции, source quote или NPC bio.
- Parser берёт реплики из **уже утверждённого** `scene.text`, позволяет повествовательные строки с `speaker=null`; признаёт диалог при не менее 2 явно именованных репликах и 2 разных именах; до 64 элементов и ограничение длины 50 000 символов.
- `presentation.scene_dialogues` опционален, построен детерминированно из текста и фиксирует `scene_text_sha256`. Импортёр **пересчитывает** ожидаемые строки из точного body: подмена имени, порядка, пропуск строки = отказ, даже при новом внешнем SHA.
- `WorldLibraryGateway` передаёт verified `List<RichDialogueTurn>?` в `WorldGameView`, `WorldPlayPage` использует существующий `DialogueStage`, локальные портреты по точной **строке имени**, прежний cursor и gating choices.
- Старые v3 без этого поля, v1/v2 — fallback, не требуют миграций. ZIP остаётся строго 4 entries, v3 **не** стал хранить отдельно визуальные recipes, полноценные NPC cards или свободные AI dialogues.
- Python `tools/bookworld/private_rich_bookworld.py` теперь имеет отдельную `_dialogue_projection` и принимает/сверяет optional `scene_dialogues` при наличии. Внешний E6d `tools/rpg_author/rich_package.py` **не обязан автоматически добавлять это поле**, пока не будет проверенного обновления pin и cross-language tests; старый проверенный v3 продолжает импортироваться без него.

**Вывод для master-плана:** утверждение «в v3 отсутствует любой структурированный диалог» теперь **устарело**. Правильно: v3 уже умеет optional signed projections `speaker/text`, но **не** полноценные `character_id/turn_id/knowledge/pose/AI policy`. Целевой единый расширенный `.bworld` (условно v4) остаётся нужен для полной кодовой визуализации и профилей NPC.

## 3. CI и опубликованный релиз: обнаружен отдельный риск

**Latest main `6711011c`:**
- **M0 #855** SUCCESS.
- **AI Story RPG CI #770** IN_PROGRESS при живой проверке; предыдущее **PR-head CI #769** SUCCESS, включая главную Dart/Flutter/Python матрицу. Пуш/слияние не объявлять post-merge PASS, пока #770 не завершён.
- **External RPG author tests #94** FAILURE на main; PR-head author tests #93 тоже FAILURE. Два конкретных упавших jobs: `author-tests` шаг **Check pinned application compatibility**, `dart-parity` шаг **Compare source indices and verify candidate against the real Dart code**. Не игнорировать и не объявлять всё зелёным.

**Проверенная техническая причина/очевидный источник риска:** `tools/rpg_author/compatibility.py.check_contract()` хеширует фиксированные пути из `tools/rpg_author/compatibility.json`; #124 изменил **три отслеживаемых файла**:
- `tools/bookworld/private_rich_bookworld.py`
- `packages/bookworld_format/lib/private_rich_bookworld.dart`
- `packages/bookworld_format/lib/private_bookworld_writer.dart`

Следовательно, текущий lock внешнего E6d **не может совпасть** с новым main, если сами новые байты не равны прежним. Это ожидаемо порождает `contract_drift`. Лог шага через API не раскрывался: точную строку CI-исключения не утверждаем, но факт failure и несовместимость файлов — подтверждены. **Не обходить защиту**, не менять hash вручную, не считать это ошибкой пользовательского `.bworld`. Устанавливаемый навык по-прежнему загружает **точный pinned E6d commit `9849c22d...`**, так что его собственная старая проверенная среда не была автоматически обновлена до нового main.

**Последний опубликованный release:** [test-build-761](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-761), target `959c8134f4ef20cd00dd4039d8d131638f502f60`, Windows portable ZIP + Android debug APK + SHA256SUMS. **Не содержит PR #124**. Новый APK с #124 не подтверждён. Точный post-merge CI / target SHA проверять перед советом скачать.

**Issue [#118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118)** остаётся OPEN; checklist в нём частично исторический (ещё просит принять уже MERGED PR #115/#117 и E5/E6). Не считать старые `[ ]` доказательством отсутствия принятых функций; реальные незакрытые требования — full-book CANON/ALTER_FATE, source-proven speaker identities, 2 real GLM/FB2 E2E на Windows/Android, offline save/replay и единый мастер без обязательных редакторов.

## 4. Что уже можно использовать и что не делать заново

**Повторно не разрабатывать:**
1. Импорт FB2 и индексатор цитат, source models, narrative book groups, исправление неотредактированных literary plans, compact book-to-RPG start page.
2. Game rules engine, typed effects, campaign_manager, SQLite, журнал/предметы/герой, event replay.
3. Диалоговый читатель, локальный cursor, portrait-slot и местные PNG, parser `RichSceneDialogue`, optional v3 signed turns, Python/Dart verification.
4. Z.ai BYOK, consent, cancellation/retry, FreeTextActionGate/AI advisor **для сопоставления с existing choices**.
5. Внешний `gameplay-audit` и `dialogue-audit` E6d.

**Добавлять в E6 только то, чего ещё нет:**
- Сквозную законченную книгу и проверенный состав персонажей/знаний; бездоказательные `speaker` строки не превращать в `world_actor_id`.
- Сценарные реплики с гарантированно корректной явно подписанной прозой. Дальнейшие `speaker_id/turn_id`, `npc_profile` и источник реплики — *новый согласованный contract*, не пытаться вставить в v3 наугад.
- Кодовый visual recipe и light motion (без PNG); AI-NPC persona/knowledge/allowed intents и optional free conversations — отдельная проверяемая схема.
- Один целевой `.bworld` с полными данными (новая строгая версия при разрешении на main BookWorld), редактор только по желанию.
- Координация изменения `compatibility.json` + pin навыка **только после** независимой сверки новых Dart/Python компиляторов и тестов; сохранить старый точный SHA в истории и не отключать guard ради зелёной CI.

## 5. Рекомендуемые действия в порядке необходимости

**P0:** подтвердить окончание post-merge CI #770, проверить причину External author #94, затем координировать совместимый tested upstream и точный E6 pin отдельным этапом, не ломая текущий пользовательский bootstrap. Не тратить время на несуществующие старые E5 save. Завершить реальную игру на двух книгах с честными CANON/ALTER_FATE и offline Win/Android E2E.

**P1:** генератор и UI договариваются о полном идентификаторе `speaker_id/turn_id/world_actor_id`, знании и источнике; v3 optional speaker/text используется как промежуточный проверенный слой, а не заменитель карточек NPC. Затем новые visual recipes/AI profiles/new self-contained format, без повторного создания уже существующей системы действий/диалогов.

**P2:** по достижении полной игры — необязательный встроенный редактор, процедурные пиксели и лёгкие анимации. Переносимые данные не должны требовать боковой импорт отдельного JSON в конечном UX.

**Не менять основной main по текущему разрешению.** Это состояние фиксируется только в независимом документе `tools/rpg_author/`.

## 6. Источники

- Main commit: https://github.com/shonentez-afk/AI-Story-RPG/commit/6711011c0e55ca14f43c0ad0cab1f9976754c08a
- PR #124: https://github.com/shonentez-afk/AI-Story-RPG/pull/124
- Main CI #770: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42211739583
- E6d external checks #94: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42211739616
- Last release #761: https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-761
- `docs/M2G3F2B2_STRUCTURED_DIALOGUE_V3_RU_2026-11-06.md`; `docs/M2G3F_UNIFIED_BOOK_RPG_ENTRY_RU_2026-11-06.md`; `docs/M2G3F2_RESUMABLE_ACT_PREPARATION_RU_2026-11-06.md`; `docs/M2G3F2B_UNCHANGED_LITERARY_REVIEW_GATE_RU_2026-11-06.md`.
