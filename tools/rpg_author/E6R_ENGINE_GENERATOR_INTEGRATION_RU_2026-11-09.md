# E6r — принятая интеграция автономного RPG-движка и ChatGPT-генератора

Дата: 9 ноября 2026. Единственный проверенный кодовый SHA: **9ddfec9a3b94444a043ef0f6270ef1ce9c9ec682**, версия генератора **0.3.0a22**.
Рабочая ветка: **feature/external-rpg-author-e6r-native-v5-unified-20261109**.

## Приёмка

[External RPG author tests #42617298626](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42617298626) — **COMPLETED SUCCESS на указанном SHA**, все 3 job успешны.

- Python author-tests: **220 основных + 37 дополнительных PASS**.
- Dart parity: **PASS** для существующего native v4/SQLite, NPC и источников.
- E6r native causal v5 E2E: **PASS**. Синтетическая русская FB2 -> единый Python ChatGPT Skill-first автор -> штатный Dart literal v5 -> source-causal review v2 -> настоящий native BookWorld v5 -> CLI/SQLite -> экспорт/импорт portable .bwsave и совпадение сохранённого состояния.

Нативная проверенная база: **92ef5d701637957e31e3e6e090f63d1e0bdb4173**, [полный native CI #1120](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681279) SUCCESS (Dart/Python/Flutter/Windows/Android).
Интеграция объединяет эту native ветку с независимо принятым E6q.1 автором через один двухродительский коммит. По отношению к нативной базе файлы apps/, packages/ и tools/bookworld/ не менялись. Игровой исполнитель только Dart.

## Единый интерфейс создания v5

В tools/rpg_author добавлена команда **author-game-v5**, которая принимает приватную FB2/TXT, создаёт неизменяемый source checkpoint, запускает только штатный native Dart для source-literal CANON, затем по приватной очереди принимает ChatGPT Skill этапы **causal_npc / causal_window / causal_literary_review** и компилирует утверждённый source-causal BookWorld v5. API внешней LLM-модели для литературного авторства не требуется.

Пример (только после явного разрешения владельца):

    python3 -m tools.rpg_author doctor
    python3 -m tools.rpg_author author-game-v5 --book /PRIVATE/book.fb2 --project /PRIVATE/project --workdir /PRIVATE/work --output /PRIVATE/game-v5.bworld --user-confirmed

Без подтверждения ответ **needs_explicit_owner_approval**, игра не создаётся. При отсутствии ответа навыка — **needs_skill_response**, без подмены моделью. При непроверенном литературном обзоре — **needs_private_literary_or_user_review**, финальный мир не создаётся. Существующий приватный причинный обзор принимается при повторном запуске только побайтово; tamper отклоняется.

**43 точных Git blob OID** теперь закрепляют вместе source authoring, native causal graph, NPC Social + delayed decision, typed freeform, ALT_FATE obligations, BookWorld v5 writer/importer, rpg_api, CLI и portable saves. Несовпадение текущего или внешнего --native-root даёт contract_drift/native_contract_drift.

Генератор согласован с нативными условиями **promise_open / promise_closed**; исполнение обещаний, память NPC и условия исходного CANON проверяет штатный Dart. Отложенные NPC-решения действуют по заранее source-reviewed правилу через 1–32 зафиксированных ходов, а не через новую Python-механику.

Для книги без проверенного NPC есть явно выбранный **--literal-only**: буквальный источник v5 без выдуманной причинной RPG. Проверяется настоящим Dart и не утверждает literary CANON. Старый author-book/v4 сохранён. IDs NPC в v4 и v5 рассчитываются из разных source-полей; **миграции старых .bwsave и NPC нет**.

## Чего этот пакет не доказывает

Синтетические CI-тексты НЕ равны содержательному аудиту двух разных настоящих русских FB2, не доказывают литературные мотивы каждой книги и физический Windows/Android игровой UX. **RpgApiContract.arbitraryBookCanon=false**; literal CANON означает буквальную проверенную последовательность текста, а не автоматически доказанный смысл. Новый native UI commit 0b942df84de8f169d5fd5c9736372d7378b0d3a1 появился параллельно и **не входит в этот закреплённый E6r SHA** до собственной приёмки и согласования.

Ни main, ни Draft PR #133 этот интеграционный пакет не изменил. Микро-PR не создавались. Skill 0.3.0a22 упакован отдельно, требуется ручная установка; не считать установленную E6p автоматически обновлённой.
