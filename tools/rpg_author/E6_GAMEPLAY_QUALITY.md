# External RPG author E6a -- game design quality gate

This is an isolated, offline, read-only extension to the E5 external authoring
compiler. It does not alter `main`, the Flutter reader, `story_core`, the
BookWorld v3 schema, or any user's campaign/save data.

## Purpose

A package that imports and reaches two endings is not necessarily a good text
RPG. E6 first tests the **mechanical value** of each candidate choice and
resource, while leaving literary meaning and enjoyable play to separate
review. We take design ideas from narrative adventures, not their source code:
use player agency, conditional dialogue, delayed consequences, and item/fact
puzzles only when appropriate for the underlying book.

## Commands

Audit any existing verified E5/E6 `.bworld v3`, without loading or migrating
its original authoring checkpoint:

```sh
python3 -m tools.rpg_author gameplay-audit \
  --bworld /private/game.bworld \
  --attribution /private/game.attribution.json \
  --output /private/gameplay_audit.json --strict
```

Or audit a source-locked accepted StoryPlan + enrichment from a project that
was **created with the exact current E6 toolchain**:

```sh
python3 -m tools.rpg_author gameplay-audit \
  --project /private/project \
  --enrichment /private/enrichment.json \
  --output /private/gameplay_audit.json --strict
```

- No `--strict`: JSON report and exit 0, even if quality warnings remain.
- `--strict`: identical JSON report and exit 3 when warnings remain.
- Corrupt, mismatched or unsupported packages fail closed with exit 2.
- `--output` is immutable and must not already exist. Reports stay private.
- The existing `build`/`verify` remains unchanged; E6a does not mutate or
  repack an existing game.

## Analyzes

- All reachable combinations of scene, story flags, inventory, stats and
  player knowledge (max 2,500; an incomplete traversal fails closed).
- Choices that are never executable; different buttons that produce identical
  next scene and identical world state.
- "Cosmetic only" branches that merge without changing any subsequently read
  world resource; branches are still meaningful if later requirements depend
  on their effect.
- Decorative stats, unused knowledge and resources with no playable use.
- Multiple *different* failure situations collapsed into one terminal scene.
- Scenes with one forced Continue and unusually early endings (non-blocking
  editorial prompts, not automatic bugs).
- Whether any reachable choice gate varies with prior player decisions.

The report contains route witnesses for diagnostic examples. A green run
means only that this finite set of **mechanical tests** found no warning.
It cannot certify compelling prose, motivations, literary faithfulness,
intuitive puzzles, character voice, or novice UX.

## What to change in the next story revision (E6b)

1. Choose the core player activity from the source's central dramatic conflict.
   Write a quest/gameplay brief **before** writing prose.
2. For each important decision specify: what changes now, which later scene
   reads the change, and how the player can recognize its payoff.
3. Make stats and facts actual prerequisites or remove them from the catalog.
   No mandatory number of fights, rooms, items or puzzles.
4. Failure can create a new obstacle or negotiation, rather than instantly
   sending several situations to the same generic game-over text.
5. For converging paths, audit dialogue, items, scene naming, NPC knowledge and
   timing in all incoming states. Static JSON cannot verify prose consistency.
6. Update StoryPlan with source-linked citations; mark added scenes as
   `EXPLICIT_ADAPTATION`. Build a **new** world identity rather than silently
   altering an existing saved campaign.
7. Run `gameplay-audit --strict`, a separate literary review, the original
   `build` + `verify`, an independent replay, and real Windows/Android QA.

## Toolchain and privacy

E5 checkpoints pin hashes of all authoring Python files. Adding an E6 module
therefore changes the toolchain ID. Do **not** rewrite old `project.json` or
`compatibility.json` hashes to bypass `toolchain_changed`. E6a directly audits
old verified `.bworld` instead. Any future E5->E6 project migration must be
separate, explicit, source-checked and lossless; original remains intact.

The package must come from a trusted private location. Keep user-owned books,
private analysis, `.bworld`, attribution sidecars and reports OUTSIDE GitHub.
No LLM/network call occurs during game auditing.

## Current Russian Frog Prince baseline

The private E5 package (not stored in GitHub) has 13 scenes, 16 choices,
4 endings, 36 reachable full-state nodes. E6 found two display-only hero stats,
three knowledge facts that never gate play, three different conflicts leading
to the same failure text, and review prompts for early endings and forced
Continue scenes. This is evidence that the E6 gate detects actual E5 design
defects, **not** proof that E6b has already produced a better RPG.