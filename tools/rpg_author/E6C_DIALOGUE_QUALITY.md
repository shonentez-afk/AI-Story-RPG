# E6c — Dialogue question QA, external compiler only

This feature is a **read-only** structural audit of an existing, verified rich
`.bworld v3` file. It does not touch `main`, the Flutter app, the established
runtime, imports, source books, or existing saved campaigns.

## Usage

```
python -m tools.rpg_author dialogue-audit \
  --bworld /private/world.bworld \
  --attribution /private/world.attribution.json \
  --contract /private/dialogues.json \
  --output /private/dialogue_report.json \
  --strict
```

`dialogues.json` is a *private*, exact-source-bound topic list:

```
{
  "format": "ai_story_dialogue_topics_v1",
  "source_fingerprint": "<the exact source SHA-256 from the world>",
  "topics": [
    {
      "question_id": "ask_frog_why",
      "source_scene_id": "frog_talk",
      "answer_scene_id": "frog_reply_why",
      "speaker": "Лягушонок",
      "one_shot": true,
      "requires_fact": null
    }
  ]
}
```

The auditor exhaustively explores reachable typed states (max 2500); validates
question destination, speaker label in the response, optional known-fact
boundary, and proves a **one-shot question cannot be used twice** on the same
campaign route. Strict mode exits 3 on warnings; invalid archive/contract
exits 2. A clean report does *not* certify prose, dialogue quality, or
character motivation, and does not imply real Android/Windows playtesting.

Question content in this manifest may contain private character names; never
include real user books or manifests in public GitHub Actions. CI uses only
synthetic minimal stories. Existing E5 checkpoint toolchain hashes are not
modified or silently migrated; run this against the compiled archive.