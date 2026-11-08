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
