# E6i — проверка PR #126: постоянная личность NPC и соответствие внешнему генератору

Дата: **2026-11-06**. Основной репозиторий: `shonentez-afk/AI-Story-RPG`.
**Источник:** [PR #126](https://github.com/shonentez-afk/AI-Story-RPG/pull/126), HEAD `a5f88437e7807239c087b184354c1fcd33c457fe`, base `4f94fc3d2dcdba3258ba5418faff37fc366b4ff9`.
**Положение на момент проверки:** OPEN DRAFT, не в `main`; M0 #864 SUCCESS; AI Story RPG CI #779 частично SUCCESS, Windows/Android build ещё IN_PROGRESS. Результаты устройств/merge подтвердить повторно.
**Граница:** основной `main`, `apps/`, `packages/`, `tools/bookworld/`, CI только READ-ONLY. Это отчёт внешнего генератора, не изменение PR #126 и не внедрение Python-совместимости.

## 1. Реальный контракт в текущем коде PR

Файл `apps/story_reader/lib/npc_character_card.dart` добавляет `NpcCharacterCard` и точный JSON из **10 полей**:
- `character_id`: regex `^npc_[a-f0-9]{32}$`; создаётся `Random.secure()` на 16 байт, непрозрачные 128 бит **при первом создании**, затем сохраняется и никогда не выводится из текста/имени/упоминаний;
- `aliases`: список строк (≤20 непустых, case-insensitive unique, длина ≤96);
- `role`: строка ≤160; `biography` ≤1200; `appearance` ≤600;
- `personality` ≤600; `speech_style` ≤400; `motivation` ≤600; `goals` ≤600;
- `portrait_asset_id`: локальный ключ `[A-Za-z0-9_-]{0,64}`, **не путь, не PNG, не URL**.

**Обратите внимание:** `display_name` сейчас хранится **снаружи карточки** в `NpcDraftProfile`, не нужно дублировать его внутрь `NpcCharacterCard`. Поле `character_id` не должно меняться при `copyWith`. `fromJson` требует точного совпадения набора ключей, новые поля добавлять без согласованной миграции запрещено.

`npc_editorial_notebook.dart`: `NpcDraftProfile.card` optional для старых черновиков; новые профили `freshProfile` выдают fresh ID; `putProfile` сохраняет предыдущий ID при обновлении старого объекта без карточки, отвергает подмену и дублирование. Validation зависит от `source_fingerprint`, подтверждённого dossier и буквального набора `mention_ids`. Старые группировки при изменении `SAME/DIFFERENT` intentionally invalidated; автоматической миграции/rebind пока нет.

`npc_editorial_page.dart`: в существующем встроенном редакторе есть полный диалог редактирования карточки (имя отдельно), все 10 полей и отображение постоянного ID. Все сведения — приватное редакторское описание, **не** доказанный канон/verified NPC knowledge и не автоматическое согласие на отправку в GLM.

`npc_knowledge_rulebook.dart`: `profileActorId(profile,dossier,fingerprint)` использует `profile.characterId`, если карточка есть; иначе старый source-based actor ID. `npc_knowledge_world_bridge.dart` внедряет actor ID в `StoryBlueprint.actors`, `initial_state.knowledge`, эффекты `learn_fact`, условия `knows_fact`. `book_id` в таком специальном переходе включает сортированный набор actor IDs, чтобы старые сохранения не загрузились под другой actor. Важно: `preview()` **требует хотя бы одно knowledge rule**. Это ещё не универсальное включение всех карточек NPC в каждый BookWorld.

Тесты добавлены к карточке, notebook, UI и реальному StoryWorld. В проверенном CI #779 Dart engine, Flutter widget/analyze, Python reference, M1.7 schema SUCCESS; Windows и Android ещё выполняются.

## 2. Сравнение с пятью согласованными разделами карточки

| Требование пользователя | В PR #126 | Что остаётся |
|---|---|---|
| Личность: постоянный ID, имя, прозвища, роль, внешность, портрет | ID, имя отдельно от карточки, псевдонимы, роль, описание, ключ локального портрета — **есть** | Не подключены автоматически процедурный sprite/портрет, portable world catalogue |
| Характер: темперамент, мотивация, цели, манера речи | Поля `personality/motivation/goals/speech_style` есть | Структурирование и источниковая проверка каждого свойства, его изменение после события |
| Связи по `character_id` | Связи сегодня существуют как **редакторские `NpcDraftNote.targetDossierId`**, не как stable character IDs | Реестр `character_id -> character_id` с типом/условиями/источниками |
| Знания по событиям | В отдельном `NpcKnowledgeRulebook` есть reviewed `learn_fact/knows_fact` и привязка actor ID | Связанный с полной карточкой каталог каждого NPC, witness/when/branch gates, строгая приватная проекция для AI |
| Происхождение: цитата / ИИ-предположение / выдумка | `NpcDraftNote.sourceAssertionId`, source validation есть для отдельных редакторских заметок | **Provenance у каждого значимого поля**, отношения, знания и реплики; явные категории, не просто общий флаг |

**Принцип:** не создавать в E6 вторую карточку, не создавать несовместимые конкурирующие NPC IDs. Этот native `NpcCharacterCard` станет выбранной основой, **если PR будет принят в main**, затем общий Python/Dart контракт и пользовательские схемы должны быть согласованы.

## 3. Две существенные задачи именно для ChatGPT-навыка

**A. Автоматическое authoring:** сейчас native `freshProfile` создаёт карту в UI после **ручной подтверждённой группировки упоминаний**, а наш навык должен создать профиль каждого нужного NPC по всей книге **сам**, без редактора. Поэтому нужен формальный переход `source_mention_group_id → reviewed_character_id → world_actor_id` с проверенными источниками, характером, знаниями, связями и пометками `SOURCE_PASSAGE/AI_INFERENCE/GAME_FICTION`. Одних строк `display_name` недостаточно.

**B. Постоянство ID при повторной сборке:** Dart использует `Random.secure`; Python не должен использовать `hash(name)`, `source_sha`, текущее положение в книге или генерировать новый ID при каждом компилировании. При первом создании **однократно `secrets.token_hex(16)`** с обязательным сохранением `character_id` в закрытом authoring checkpoint/project_snapshot, затем поддерживать тот же ID при reopen и validate uniqueness before ZIP assembly. Новый идентификатор для нового персонажа; перепривязка source clusters — только явная проверенная операция, никогда silently by name.

**Сейчас НЕ делать:** подсовывать `npc_character_card.json` в текущий rich `.bworld v3` (4 строгих ZIP paths), копировать `NpcCharacterCard` в Python как независимую schema, менять `compatibility.json` или pinned skill SHA E6d без нового parity test suite. Будущий single-file расширенный BookWorld должен включать проверенные NPC cards и связывать их с existing story_core actor/choice/knowledge и структурированными диалогами, но только в согласованной версии формата.

## 4. Порядок ближайшей синхронизации

1. Ждать exact-head CI #779: Windows + Android должны пройти; только потом считать PR готовым к merge, после merge проверить real main SHA и post-merge CI.
2. Отдельно в основном приложении — сделать `speaker -> character_id` c source evidence, отношения по stable ID, per-field provenance, bounded read-only NPC context for future API; проверить таймлайн знаний/событий и отсутствие подмены личности.
3. Для внешнего генератора после merge — написать **не независимый `npc_profile` runtime**, а адаптер к утверждённой native shape; idempotent authoring checkpoint, source provenance, tests Python и Dart для одного и того же образца; обновить pinned E6 skill только после full contract parity.
4. Не задерживать полное создание `.bworld` и литературный E2E двух книг ради ручного UI: редактор после импорта необязателен, именно навык делает все карточки.

**Суть:** PR #126 реально устраняет проблему текучей личности NPC и связывает постоянный ID с `StoryWorld`, но пока **не выполняет автоматически весь путь «навык → полный набор NPC → self-contained .bworld → свободный AI-диалог/пиксельный рендерер»**. Это отдельные проверяемые этапы.

## Ссылки

- PR и diff: https://github.com/shonentez-afk/AI-Story-RPG/pull/126
- Branch: https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/m2g3f2b4-stable-npc-character-card-20261106
- Exact-head CI #779: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42218314154
- M0 #864: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42218313998
- Основная спецификация E6: `tools/rpg_author/AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md`
