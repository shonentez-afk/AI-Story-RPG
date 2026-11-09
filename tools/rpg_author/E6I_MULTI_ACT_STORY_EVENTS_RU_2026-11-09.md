# E6i 0.3.0a8: source-locked multi-act storytelling for native BookWorld v4

Scope: external tools/rpg_author and tests/rpg_author only. No modifications
to main, Flutter, independent Dart engine, game save formats or native CI.

## Implemented authoring contract

Version rpg_author_v4_acts_v1, explicit in build-extended --extension and
audit-extended --extension. E6h v4 bridge contract is still supported.

The proposal contains format, source_fingerprint, story_sha256,
enrichment_sha256, base_blueprint_sha256, editorial_review, acts and
initial_state. Editorial review includes user_confirmed=true,
transition_causality_reviewed=true, character_continuity_reviewed=true,
literary_canon_verified=false. Reviews are user declarations, not proof.

Acts are ordered by chapter and pinned to ORIGINAL choice IDs from an
accepted v3 project. Each includes id, after_choice_id, chapter_start,
chapter_end, entry_scene_id, scenes. Scenes require id, event_id, title,
text, chapter_index, origin, assertion_ids, choices. Choices require id,
label, next_scene_id, conditions, effects, effect_assertion_ids.

Each event must cite its own distinct real source assertion and quote hash.
A SOURCE_PASSAGE source must be NARRATED and visible by its own chapter.
REPORTED and INFERRED cannot automatically authorize a source event.
Each act must cover each declared chapter with such a source scene,
include 2..128 scenes, at least one genuine branching decision, at least
one state-changing effect, all reachable events and an acyclic route to
the original destination via the special @exit target.

Effects and conditions are strictly bounded to the existing Dart DSL.
Supported conditions: flag_is, has_item, stat_at_least, knows_fact,
tick_at_least. Supported effects: set_flag, grant_item, consume_item,
stat_delta, learn_fact for player, advance_time. Each effect must be
paired with a source assertion ID from the same event; consume_item
requires a has_item condition. No new item/flag/fact/stat/actor can
be created beyond the base reviewed catalogs. An NPC learn_fact
requires its own actor-scoped source review and is explicitly rejected.

Runnable CLI commands:
python3 -m tools.rpg_author doctor
python3 -m tools.rpg_author audit-extended --project /private/project --enrichment /private/overlay.json --extension /private/acts.json
python3 -m tools.rpg_author build-extended --project /private/project --enrichment /private/overlay.json --extension /private/acts.json --output /private/game.bworld
python3 -m tools.rpg_author verify-extended --input /private/game.bworld --attribution /private/game.attribution.json

## Acceptance and exact scope

A purely synthetic original FB2 with three indexed chapters, two acts,
four unique cited events, gated knowledge, multiple reachable results
and native SQLite replay/save is included in Dart parity. Python negative
tests prohibit quote repetition, false source provenance, future
citations, graph cycles, fake NPC grants and invalid typed effects.
At document creation exact-code CI is NOT yet verified.

Literary/canonical correctness, real large FB2 adaptation, GLM, actual
authoring of new NPC social memories and device Windows/Android E2E
remain unverified. This is a mechanism for authoring source-bound
story acts, not a fully automatic book-to-game promise.
## ACCEPTED exact-code integration (9 November 2026)

External code SHA 96d4cfac79586bfb58f2302ed5192a830fac2ab9 includes both accepted source-bound multi-act generator
and an reviewed native PR #133 integration SHA 081fc365efac030be25d8b75aca0ba305a6bcc6c.
GitHub Actions #42540898271 COMPLETED SUCCESS: author-tests and dart-parity SUCCESS.
135 Python unit tests OK, 37 supplemental tests OK. Dart runtime really compiled
v4 world from a three-chapter synthetic FB2, replayed three routes with
source-verified choices and actor=player knowledge gates, and verified
SQLite campaign reopen/fork/portable save. The previous rich-v3,
203-scene E6h, and native NPC v5 regression remain successful.
Installed ChatGPT skill E6d is not automatically upgraded.

Not proven: 3 real chapters are not a long novel; a confirmed source citation
does not prove semantic correctness; an editorial user declaration is not a
cryptographic author/canon attestation. New NPC actor-scoped grants in E6i
remain fail-closed and require their own literary/source review.
