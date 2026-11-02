# M2b3a — проверяемые доказательства, неопределённость и защита от спойлеров

Дата: 2026-11-02. Ветка: `feat/m2b3a-provenance-evidence-20261102`. База: проверенный M2b2, PR #8 merged в main как `e704cdf47d1b30816c65ac68a6ab49315597aa4e`.

## Реальная реализация
- `apps/story_reader/lib/source_evidence_graph.dart` — чистый Dart модуль `SourceEvidence`, `SourceEvidenceGraph`, `PossibleEntityMatch`.
- Только 4 типа проверяемых **кандидатов**: CHARACTER, LOCATION, FACT, EVENT. Это не генератор повествования и не автоматическое установление канонических фактов. `EvidenceStatus.INFERRED` при любом автоматическом/ручном предложении; `CONFIRMED` возможен только после явного вызова `review`; существуют `CONFLICTED` и `REJECTED`. Выдуманные утверждения `INVENTED` не маскируются под исходные доказательства, должны жить в отдельном слое адаптации позже.
- При создании кандидат обязан совпасть с точным поддиапазоном `SourceChunk`: edition fingerprint, chapterId, block, absolute UTF-16 [start,end), SHA-256 выбранной цитаты, устойчивый ID; лимит цитаты 180 UTF-16 единиц, проверка surrogate bounds. Checkpoint `ai_story_source_evidence_m2b3a_v1` (JSON + SHA-256) проверяет все ссылки на неизменённую книгу; не является криптографической подписью/подтверждением авторства.
- `fromReviewedMentions` принимает только разрешённые человеком текстовые упоминания из M2b1 и всё равно оставляет новые записи **INFERRED**: подтверждённый текст ≠ истинный факт мира. Повторяющееся написание имени в разных главах даёт только `PossibleEntityMatch` с `identityConfirmed=false`, никаких автоматических слияний NPC.
- `EvidenceSpoilerGate`: CHAPTER (только после заданной главы), AFTER_EVENT (нужен и номер главы, и подтверждённое игровое событие), HIDDEN (не показывать игроку). `visibleToPlayer` возвращает только явно CONFIRMED, разрешённые по gate записи; не раскрывает секреты до прохождения. Применять его при будущем выводе данных — новый модуль пока НЕ подключён к игровому UI, не обходить этим обещанные знания NPC.
- `SourceEvidence.propose` принимает точные spans для будущих FACT/EVENT извлекателей, но **никакой источник ИИ или алгоритм смыслового извлечения фактов/событий на M2b3a не создан**. `gameplay_coverage=0`, `can_publish_bookworld=false`.

## QA
- `apps/story_reader/test/source_evidence_graph_test.dart`: принятые упоминания без превращения в канон, два спорных совпадения между главами, FACT/EVENT spans, временные и событийные границы, hidden policy, чужая редакция, tamper с пересчитанным внешним SHA, Unicode/invalid ranges, повторные IDs, конфликтные/отклонённые статусы.
- Принятие **только после** GitHub Actions по точному commit: Python/Dart/story-core, Flutter analyze и widget, Android APK, Windows portable. Ручной Android/Windows, screen readers, power-loss, полная проверка доступности SKIP.

## Следующий M2b3b
Источниковый extractor для FACT/EVENT с явной неопределённостью, межглавный граф персонажей/вариантов имён и конфликтов, проверки provenance и temporal/spoiler policy, human review UI в существующем едином экране подготовки; состояние persist только в приватном хранилище после атомарной записи. Затем intermediate blueprint + полный валидатор; не создавать .bworld из regex-находок и не менять пользовательские сохранения.
