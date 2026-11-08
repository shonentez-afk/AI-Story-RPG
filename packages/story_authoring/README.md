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

**Current limitation:** this slice extracts source import/index and verified
compilation, NOT the entire intermediate semantic/causal/AI authoring pipeline.
Literary event/character review, long-book StoryPlan, and UI checkpoints still
live inside the Flutter app. They must move to this Dart package without a
parallel compiler before calling the COMPLETE creator autonomous.
```
