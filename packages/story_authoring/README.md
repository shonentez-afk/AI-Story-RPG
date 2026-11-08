# Standalone source-locked authoring (first independent slice)

**No Flutter, cloud, Python or second game runtime.** This package now OWNS
the existing TXT/FB2/FB2.ZIP parser, UTF-16 decoder and exact source index.
The Flutter reader re-exports these same classes; no duplicated algorithms.

```sh
cd packages/story_authoring
dart pub get
dart test
dart run bin/author_book.dart inspect-source /private/book.fb2
dart run bin/author_book.dart build-reviewed /private/book.fb2 /private/review.json /private/book.bworld
dart run bin/author_book.dart verify-world /private/book.bworld
```

`review.json` contains exactly `{"blueprint": {...}, "provenance": {...}}`,
with existing strict rich-v3, source-verified, *reviewed* game mechanics.
The native writer + independent rich-v3 reader verify all actual UTF-16
quotes before creating the package. No model answer is trusted as the original
source. If validation fails, no destination file is truncated.

**Standalone offline semantic pass:** `dart run bin/author_book.dart scan-source /private/book.fb2 --checkpoint /private/scan.json`. This reuses the SAME verified mention, evidence, semantic, chronology and NPC-dossier models as Flutter. The checkpoint has embedded private quote snippets and is fingerprint-bound; the stdout JSON contains only counts. The scan yields review CANDIDATES, not approved canon or a playable RPG.

**Current limitation:** this slice extracts source import/index, offline source candidate analysis and verified
compilation, NOT the entire intermediate semantic/causal/AI authoring pipeline.
Literary event/character review, long-book StoryPlan, and UI checkpoints still
live inside the Flutter app. They must move to this Dart package without a
parallel compiler before calling the COMPLETE creator autonomous.
```

## A portable AI / human proposal path (no provider dependency)

Generate the **source-only** JSON from the already indexed book using
`SourceLockedEventOutline.emptyDraft(index)`. Fill `events` with literal
quotes and UTF-16 offsets; the `scanned_chunks` list must cover EVERY chunk
in order and match the source hashes. The `label` is an **untrusted
interpretation** even when its quote is genuine.

```sh
dart run bin/author_book.dart review-plan /private/book.fb2 \
  /private/events.json /private/model_reply.json /private/plan_review.json
```

The third argument is a structured model or human proposal using the same
15-key contract as the existing Z.ai plot-dilemma service (or
`{"applicable":false}`). The **same pure-Dart validator** is now used by
the app's Z.ai adapter and this CLI; the local pipeline checks exact quote
positions, model-selected event allowlist and scenario effects. A formal
success is still `DRAFT_NEEDS_EDITORIAL_REVIEW`: human proof of literary
meaning and the native strict BookWorld compiler are separate gates.
No API key, secret, network permission, or full-book upload is involved.

## Native compilation and NPC authoring independent of Flutter

The original strict `PrivateClassicScenarioTranslator`, `NpcEditorialNotebook`,
`NpcKnowledgeRulebook`, source-locked item/NPC bridges and
`compileReviewed*BookworldInWorker` live in this Dart package. These are
**the same exact code paths** previously hosted in Flutter. The mobile/desktop
application imports compatibility exports; the standalone compiler uses
`dart:isolate` to perform CPU-heavy ZIP/SQLite operations without Flutter
`compute`. All source, social knowledge, item custody, signed dialogue and
private-only checks remain enforced by the existing format writer/importer.

Flutter can supply UI checkpoints and consent, but cannot bypass the independent
compiler, and a cloud model answer is never treated as an accepted NPC claim.
Full bookwide prose/hero selection and all model adapters are still being
migrated; this step alone does **not** certify a generated game as CANON.

## Import a reviewed editor project and compile without the app

```sh
dart run bin/author_book.dart build-draft /private/book.fb2 \
  /private/reviewed_checkpoints.json /private/game.bworld
```

`reviewed_checkpoints.json` is a PRIVATE JSON envelope
`ai_story_portable_reviewed_draft_v1` containing the exact
`source_fingerprint`, `evidence`, `catalog`, `editorial`, `draft`
checkpoint strings and `hero_name`. Those fields must already have passed
the **existing human editorial** process. Optional `npc` holds confirmed
identity relations, notebook, knowledge rules, signed quote hashes, items,
social mechanics and reviewed dialogue turns. Zero-NPC worlds omit this field.

The compiler re-opens each checkpoint against the exact imported book, runs
the original editorial / state preflight, executes the SAME native v2/v3
writer in Dart isolates, and reopens the final rich-v3 archive. Private
literary rights, consent and source constraints are preserved. The output is
a playable PRIVATE structural adaptation, **not** automatically accepted
literary CANON. External/freeform model proposals have no automatic access
to this build path.

## Complete source-locked multi-act/NPC assembly is a pure Dart API

The original `StoryPlanTrialCompiler`, `MultiActTrialCompiler` and
`BookwideNpcCampaignAuthoring` now live here. The Flutter app reexports
**the same types**. Causal/chronology/cross-act source audits, role identity,
confirmed literary concerns, approved scene prose and all-route NPC dialogue
use the same `bookworld_format` and `story_core` rules, without an app import.
The NPC ZIP compiler uses Dart `Isolate.run`, not Flutter `compute`.

**Not a complete book automator yet:** CLI still requires author-reviewed
source claims, scenario/role and provenance. Z.ai network/consent UI and
checkpoint file adapters remain outside the pure Dart library. The strict
format limit (e.g. 192 scenes) and CANON/role-mode rules remain unchanged.

## Complete-book AI analysis is a portable model callback, not a Flutter loop

`PortableWholeBookAnalyzer`, `ZaiWholeBookConsentManifest`,
`SourceSemanticWindowPlanner`, the exact SHA-locked
`ZaiWindowReviewQueue` and event coverage projection live in pure Dart.
The Flutter `ZaiAutoWholeBookAnalysis` is now only the Z.ai HTTP/OS storage
adapter. A local model can implement the same bounded
`PortableWholeBookWindowPreview` callback without importing Flutter or
copying the editor's queue algorithm. Each invocation requires explicit
consent to the full source-window manifest; cancellation stops further calls;
checked results are written per window before progress is reported.

No provider candidate is automatically canon, character identity, evidence of
NPC knowledge or a permitted game-state change. Real book-wide literary
meaning and cross-act causality remain separate reviewed build gates.
