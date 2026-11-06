# E6d — проверка optional NPC-grants rich-v3 для PR #131 (2026-11-07)

**Контракт:** [PR #131](https://github.com/shonentez-afk/AI-Story-RPG/pull/131), [его описание](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/p0-rich-v3-npc-knowledge-parity-20261107/docs/P0_NPC_RICH_V3_KNOWLEDGE_CONTRACT_RU_2026-11-07.md). До merge версия находится в draft. **Обновление только tools/rpg_author**, нативные apps/packages/tools/bookworld/основной CI не изменяются этим согласованием.

## Диагноз

[External RPG author #122](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42278157974) остановился **до тестов** на `contract_drift`. Ровно три прежних sha256 E6d не соответствовали новым исходникам, которые были изменены в PR #131. Это правильная защита: нельзя обходить отключением проверки.

## Проверенное изменение в PR #131

В `.bworld v3` остаются те же **четыре ZIP-файла**, старые player-only миры сохраняют прежнюю структуру. Появились **опциональные**, но строго проверяемые поля:

- `manifest.json`: `npc_knowledge_format = ai_story_npc_knowledge_grants_v1`, только если у мира NPC.
- `source/provenance.json`: `npc_knowledge` со source-locked `grants`, версией, `user_confirmed`, `literary_canon_verified=false`, source fingerprint; в `presentation` — `scene_dialogue_knowledge` поверх точных подписанных `scene_dialogues`.
- `scenario/blueprint.json`: `actors` содержат только player + постоянные `npc_<32hex>`; `learn_fact` и `knows_fact` работают по конкретному NPC; `initial_state.knowledge` пусто по каждому актёру.
- Отказ при фальшивой цитате, неразрешённом получателе, пропущенном grant, неподписанной реплике, предзнании или имитации чужих знаний; `gameplay_review` одновременно с новым grant пока запрещён.

## Что делает данный patch

1. Pin для этих трёх **конкретных** файлов обновлён по проверенному source SHA256 на точном HEAD PR #131. Старые семь зафиксированных файлов оставлены без изменений.
2. `tools/rpg_author/npc_compatibility_probe.py` синтетически создаёт проверенный optional NPC v3, проверяет старый player-only v3, 4-entry ZIP, неизменность и встроенный E6d `verify_rich_bundle` с attribution sidecar.
3. Отдельно проверяются девять негативных случаев. В `doctor` результат обозначен **только** как Python+sidecar probe; не подменяет реальный GLM/Windows/Android E2E и не утверждает автоматическое authoring NPC.
4. Прежний `rich_package.compile_rich_from_project` по умолчанию по-прежнему создаёт **player-only** v3 без выдуманных одобрений. Чтобы автоматически генерировать NPC из книги, нужна отдельная подтверждённая пользователем StoryPlan→NPC-grants подготовка, а не вставка `user_confirmed=true` в продуктивный код.

## Точная проверка

- На PR #131 native CI #849 и M0 #934 **SUCCESS** по exact HEAD `26b5c6ef6d347c7a526a189a4b7281129595a826` до данного patch. Native PR тесты отдельно проверяют Python→Dart и Dart→Python actual NPC-v3 bytes.
- После commit **обязательно дождаться результатов External RPG author** (author-tests и dart-parity) на **точном новом HEAD**, затем сверить main CI/M0. Никаких выдуманных результатов.
- Пользовательские приватные книги, модельные ответы и старые E5 миграции не нужны.

## Границы

Закреплённый отдельный ChatGPT skill E6d на `9849c22d18e2761b49766b0c213b4a3fb3fe053b` остаётся **без изменений**. Синхронизировать его только после точного нового HEAD, пройденных тестов и отдельной процедуры pinned bootstrap/parity. Правки не отправлять в `main` минуя обычный PR.
