# M2c: editorial review, durable checkpoints and honest readiness

Date: 2026-11-02. Base: PR #21 merged into main (code `a8b016e3bd4ebf6855fe7b81cc861b566b078a3b`).
PR #21 exact head `69fc30289f0131b130bd448d56374b2ffc907fd8`,
Actions `41447576581` 6/6 PASS, Flutter **187/187 PASS**, Windows+Android PASS,
M0 `41447576604` PASS. New editorial work is independent and still requires its own CI.

## Why this is needed before real AI

A detected passage, a claimed event and validated game canon must be three
different states. `SemanticEditorialVerdict.canonCandidate` explicitly means
**requires additional cross-chapter verification**, not CONFIRMED world truth.
AI output is never allowed to mutate `.bworld`, `.bwsave` or original book data.

## New code in this branch

- `source_semantic_editorial_review.dart`: immutable user editorial
  `passageOnly/canonCandidate/disputed/rejected`; strict source fingerprint,
  exact catalog hash and JSON status, safe round trip; never `canPublishBookworld`.
  A changed catalog or book edition rejects the old review.
- `source_analysis_checkpoint_repository.dart`: additive scopes
  `semanticCatalog`, `semanticEditorial`, `intermediateDraft`, separate
  private folders, same atomic write mechanics, without altering the four
  previous folders and game saves.
- `preparation_readiness_report.dart`: read-only actual status of source
  coverage, mentions, narrative evidence, semantic proposals, editorial
  decisions, causal draft, rights, production compiler and absent AI. Zero
  gameplay coverage and no claim of automatic network access.
- `pre_ai_editorial_readiness_test.dart`: textual quote vs real canon, explicit
  user review and cancellation, invalid source/catalog, tampered JSON, separate
  physical scopes, preflight blocker report.

## Still missing, independent gates

- Real text-wide model semantic inference, cross-book identities, character
  knowledge, auto timeline verification, model provider opt-in and API budgets.
- M2d production `.bworld` builder/importer with exact provenance and safe
  personal/public rights modes; original_demo contract is unchanged.
- Full one-button UX orchestration for the long-running pipeline and human
  decisions, and Windows/Android manual E2E for a genuine user source.
- Do not claim the user's arbitrary book is playable in PR #22. Current
  branch is **CODE / CI PENDING** until exact-head checks and gated merge.
