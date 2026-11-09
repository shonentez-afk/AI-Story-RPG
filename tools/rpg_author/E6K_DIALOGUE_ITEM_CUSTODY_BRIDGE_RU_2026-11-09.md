# E6k — NPC dialogues and item custody across reviewed multi-act BookWorld v4

9 November 2026. Version `0.3.0a10`. External Python generator only,
native Git pin from accepted E6j: 081fc365efac030be25d8b75aca0ba305a6bcc6c.
No native/Flutter/main/CI changes. E6j v2, E6i, E6h and rich-v3
remained separate explicit input versions with their own acceptance.

## Reused existing native engine work

- `RichSceneDialogue`: exact two-speaker text from signed blueprint;
  required scene SHA and order, not separately generated transcript.
- `RichNpcDialogueKnowledge`: actor-scoped fact and prior-choice gating,
  social memory, trust and runtime redaction; never leak speaker name
  or portrait until source-verified knowledge has been earned.
- `RichNpcSocialContract` v5: original grant_item source acquisition,
  actual has_item+consume_item player choice, witnessed transfer to NPC.
- `RpgGameApi` through `LocalRpgGameApi`: the ONLY live runtime
  used in Dart parity for redacted speech, NPC custodian and portable save.
- `SourceLockedDialogueSpeakerAudit` findings: name or source occurrence
  is not authority to claim speaker identity, fact knowledge or canon;
  E6k demands a pre-existing verified permanent character_id.

## Explicit proposal schema

Use `build-extended --npc-review /private/base.json --extension /private/e6k.json`.
The v3 extension contains all previous v2 fields plus `npc_scene_review`.
Review fields: `format: rpg_author_v4_npc_scene_review_v1`,
`source_fingerprint`, `base_npc_act_review_sha256`, `user_confirmed`,
`literary_canon_verified=false`, `dialogues`, `item_grants`, `item_transfers`.
All lists are explicit, bounded, source-cited and non-empty.

`dialogues`: each has `scene_id`, `turns`; each turn has
`turn_index`, `speaker`, `actor_id`, `required_fact_ids`; knowledge-bearing
NPC lines additionally have `required_social_memory_id`,
`minimum_trust_to_player`, `required_prior_choice_id`, `assertion_id`,
`private_fiction_confirmed=true`. Source quote SHA is computed from
the original verified book index by the generator, not supplied by AI.
Every signed source passage scene gets exact complete speaker review;
no name-only speaker/portrait inference. Source citations ground
the learning action; they do NOT prove invented speech is book canon.

`item_grants`: source scene/choice/item/assertion_id; must refer to
an original SOURCE_PASSAGE scene that actually grants an item.
`item_transfers`: authored scene/choice/item/from_actor_id/to_actor_id/
assertion_id. E6k currently supports only player -> already-known NPC
when the actual signed choice has `has_item` and `consume_item` for
the specific item, a witnessed present NPC and an earlier exact item
source. Duplicated grants, forged owners and missing inventory gates
are rejected. Existing NPC custody records are not silently migrated.

Compiled world remains `format_version=4`, private-only, signed by
the existing native Dart writer and imported by the existing Dart
`RichPrivateBookworldImporter`. Gameplay state and NPC owners
are never reimplemented by Python. No extra ZIP members or
unreviewed migration of v3/v4 save files.

## Acceptance

One original synthetic RU FB2 with three chapters, two acts, real
per-choice actor memory/fact gates, two-person signed dialogue and
rope acquisition -> witnessed NPC transfer. Python negative tests
and Dart `LocalRpgGameApi` check old hidden line, shown earned line,
permanent portrait actor ID, visible NPC inventory owner, opposite
branch, SQLite portable save and unchanged older regressions.
At commit creation exact-code CI has NOT yet run. Do not mark READY.

Not a full-book literary quality claim; no two real private RU FB2
have been verified, no portrait images generated, no actual model
written dialogue, and no physical Android/Windows integration.
Installed ChatGPT RPG skill remains pinned to E6d, not upgraded.

Next: either full source-locked whole-book literary trials and
multi-character source scrutiny, or a separately scoped E6l
for native-reviewed reply options/complex item returns, after
accepting this E6k on exact SHA.
