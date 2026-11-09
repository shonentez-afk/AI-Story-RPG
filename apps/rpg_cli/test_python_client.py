"""Real cross-language Python -> Dart HTTP -> canonical SQLite game test.

Uses only a synthetic source-reviewed fixture. Never uploads user book text.
"""
from __future__ import annotations

import base64
import json
from pathlib import Path
import select
import subprocess
import tempfile
import unittest

from python_client import RpgClientError, RpgHttpClient


HERE = Path(__file__).resolve().parent
FIXTURE = HERE.parent.parent / "artifacts/bookworld/book_private_rich_items_python.bworld"
V4_FIXTURE = HERE.parent.parent / "artifacts/bookworld/book_private_extended_dart.bworld"


class PythonRemoteRpgTests(unittest.TestCase):
    def test_python_client_can_play_replay_and_restore_without_flutter(self):
        self.assertTrue(FIXTURE.is_file(), str(FIXTURE))
        with tempfile.TemporaryDirectory(prefix="rpg_python_client_") as private_dir:
            child = subprocess.Popen(
                ["dart", "run", "bin/rpg_server.dart",
                 "--store", str(Path(private_dir) / "store")],
                cwd=HERE,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            try:
                ready, _, _ = select.select([child.stdout], [], [], 90)
                self.assertTrue(ready, "Dart loopback host did not start")
                line = child.stdout.readline()
                self.assertTrue(line.startswith("{"), "Dart startup did not return JSON")
                info = json.loads(line)
                self.assertEqual(info["status"], "listening")
                client = RpgHttpClient(info["endpoint"], info["token"])
                capabilities = client.call("capabilities")
                self.assertTrue(capabilities["offline_play"])
                self.assertFalse(capabilities["arbitrary_book_canon"])
                self.assertFalse(capabilities["dynamic_ai_game_master"])

                world = client.call("install_world", {
                    "archive_base64": base64.b64encode(
                        FIXTURE.read_bytes()).decode("ascii")
                })
                receipt = client.call("inspect_world", {
                    "archive_base64": base64.b64encode(
                        FIXTURE.read_bytes()).decode("ascii")
                })
                self.assertTrue(receipt["is_private"])
                self.assertFalse(receipt["literary_canon_proven"])
                world_hash = world["world_hash"]
                self.assertEqual(len(world_hash), 64)
                session = client.call("start", {"world_hash": world_hash})
                self.assertEqual(session["revision"], 0)
                self.assertIn("choices", session)
                self.assertIn("npc_encountered", session)
                campaign_id = session["campaign_id"]
                wait_label = next(
                    choice["label"] for choice in session["choices"]
                    if choice["id"] == "wait"
                )
                offers = client.call("suggest_action", {
                    "campaign_id": campaign_id,
                    "text": wait_label,
                })
                self.assertEqual(offers["offers"][0]["choice_id"], "wait")


                denied = client.call("choose", {
                    "campaign_id": campaign_id,
                    "choice_id": "help",
                    "action_id": "py_denied",
                    "expected_revision": 0,
                })
                self.assertFalse(denied["applied"])
                self.assertEqual(denied["revision"], 0)

                moved = client.call("choose", {
                    "campaign_id": campaign_id,
                    "choice_id": "wait",
                    "action_id": "py_wait",
                    "expected_revision": 0,
                })
                self.assertTrue(moved["applied"])
                self.assertEqual(moved["revision"], 1)
                self.assertEqual(len(moved["journal"]), 1)
                reopened = client.call("view", {"campaign_id": campaign_id})
                self.assertEqual(moved["journal"], reopened["journal"])
                saved = client.call("export_save", {
                    "campaign_id": campaign_id
                })["save_text"]
                preview = client.call("preview_save", {
                    "world_hash": world_hash,
                    "save_text": saved,
                })
                self.assertEqual(preview["revision"], 1)
                imported = client.call("import_save", {
                    "world_hash": world_hash,
                    "save_text": saved,
                })
                for field in (
                    "revision", "inventory", "journal", "npc_encountered"
                ):
                    self.assertEqual(imported[field], moved[field], field)
                self.assertEqual(len(client.call("worlds")["worlds"]), 1)
                # Same external client can import the REAL native Dart v4,
                # not a rewritten Python gameplay approximation.
                self.assertTrue(V4_FIXTURE.is_file())
                v4_b64 = base64.b64encode(
                    V4_FIXTURE.read_bytes()).decode("ascii")
                v4_preflight = client.call("inspect_world", {
                    "archive_base64": v4_b64,
                })
                self.assertEqual(v4_preflight["format_version"], 4)
                self.assertGreaterEqual(v4_preflight["scene_count"], 3)
                self.assertFalse(v4_preflight["literary_canon_proven"])
                v4_install = client.call("install_world", {
                    "archive_base64": v4_b64,
                })
                v4_started = client.call("start", {
                    "world_hash": v4_install["world_hash"],
                })
                self.assertEqual(v4_started["revision"], 0)
                self.assertIn("npc_encountered", v4_started)
                self.assertIn("journal", v4_started)
                self.assertIn("scene_origin", v4_started)

                with self.assertRaises(RpgClientError):
                    client.call("import_save", {
                        "world_hash": "f" * 64,
                        "save_text": saved,
                    })
            finally:
                if child.stdin:
                    child.stdin.close()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
                if child.stdout:
                    child.stdout.close()
                if child.stderr:
                    child.stderr.close()


if __name__ == "__main__":
    unittest.main()
