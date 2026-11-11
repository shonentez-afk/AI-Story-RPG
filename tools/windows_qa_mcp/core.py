"""MCP-independent QA protocol, evidence and safety boundary.

No Windows packages are imported here. The UI adapter is injected for tests.
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class QAError(ValueError):
    """An actionable error safe to show in a model tool result."""


@dataclass(frozen=True)
class Config:
    exe: Path | None
    output: Path
    allow_input: bool

    @classmethod
    def from_env(cls) -> "Config":
        raw = os.environ.get("AI_STORY_QA_EXE", "").strip()
        root = os.environ.get("AI_STORY_QA_OUTPUT", "").strip()
        return cls(
            exe=Path(raw).expanduser().resolve() if raw else None,
            output=(Path(root).expanduser() if root else Path.home() / "AIStoryRPG-QA").resolve(),
            allow_input=os.environ.get("AI_STORY_QA_ALLOW_INPUT") == "1",
        )


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def clean_label(value: str, max_len: int = 48) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", value.strip()).strip("-_")[:max_len]
    return slug or "qa"


class Evidence:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.run_dir: Path | None = None
        self.name = ""
        self.started_at = ""
        self.actions: list[dict[str, Any]] = []
        self.checks: list[dict[str, Any]] = []
        self.screenshots: list[dict[str, Any]] = []
        self.notes: list[dict[str, Any]] = []

    def begin(self, name: str) -> dict[str, Any]:
        if not name or len(name) > 120:
            raise QAError("Use a run name of 1..120 characters")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        folder = self.root / (stamp + "-" + clean_label(name))
        folder.mkdir(parents=True, exist_ok=False)
        self.run_dir = folder
        self.name = name
        self.started_at = utc_now()
        self.actions = []
        self.checks = []
        self.screenshots = []
        self.notes = []
        return {"run": name, "directory": str(folder), "started_at": self.started_at}

    def action(self, operation: str, info: dict[str, Any]) -> None:
        if self.run_dir is not None:
            self.actions.append({"at": utc_now(), "operation": operation, **info})

    def check(self, description: str, passed: bool, observed: list[dict[str, Any]]) -> dict[str, Any]:
        if self.run_dir is None:
            raise QAError("Call qa_begin before recording assertions")
        result = {
            "at": utc_now(), "description": description, "passed": passed,
            "observed": observed[:8],
        }
        self.checks.append(result)
        return result

    def note(self, scenario: str, status: str, reason: str) -> dict[str, Any]:
        if self.run_dir is None:
            raise QAError("Call qa_begin before recording a blocked/inconclusive scenario")
        if status not in ("BLOCKED", "INCONCLUSIVE", "SKIPPED"):
            raise QAError("qa_note can only record BLOCKED, INCONCLUSIVE, SKIPPED; PASS requires qa_assert")
        if not scenario.strip() or len(scenario) > 120 or not reason.strip() or len(reason) > 240:
            raise QAError("Provide a short scenario (1..120) and reason (1..240)")
        item = {"at": utc_now(), "scenario": scenario, "status": status, "reason": reason}
        self.notes.append(item)
        return item

    def screenshot(self, label: str, png: bytes) -> dict[str, Any]:
        if self.run_dir is None:
            raise QAError("Call qa_begin before screenshots")
        if not png.startswith(b"\x89PNG\r\n\x1a\n") or len(png) > 8_000_000:
            raise QAError("Invalid or oversized PNG screenshot")
        name = f"{len(self.screenshots)+1:03d}-{clean_label(label)}.png"
        target = self.run_dir / name
        target.write_bytes(png)
        item = {"file": str(target), "sha256": hashlib.sha256(png).hexdigest(), "bytes": len(png)}
        self.screenshots.append(item)
        return item

    def report(self) -> dict[str, Any]:
        if self.run_dir is None:
            raise QAError("Call qa_begin before generating a report")
        passed = sum(1 for c in self.checks if c["passed"])
        failed = len(self.checks) - passed
        # Missing evidence may never masquerade as an all-green QA report.
        status = ("FAIL" if failed else "BLOCKED" if any(n["status"] == "BLOCKED" for n in self.notes)
                  else "INCONCLUSIVE" if any(n["status"] == "INCONCLUSIVE" for n in self.notes)
                  else "PASS" if self.checks else "NOT_TESTED")
        summary = {
            "run": self.name, "started_at": self.started_at, "finished_at": utc_now(),
            "checks_total": len(self.checks), "checks_passed": passed,
            "checks_failed": failed,
            "status": status,
            "actions": self.actions, "checks": self.checks, "screenshots": self.screenshots,
            "notes": self.notes,
        }
        json_file = self.run_dir / "report.json"
        md_file = self.run_dir / "report.md"
        json_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        markdown = [f"# Windows UI QA: {self.name}", "", f"Status: **{summary['status']}**", "",
                    f"Assertions: {passed}/{len(self.checks)}", "", "## Checks", ""]
        for check in self.checks:
            markdown.append(("- PASS: " if check["passed"] else "- FAIL: ") + check["description"].replace("\n", " "))
        markdown.extend(["", "## Blocked / inconclusive / skipped", ""])
        for note in self.notes:
            markdown.append(f"- {note['status']}: {note['scenario']} — {note['reason']}".replace("\n", " "))
        markdown.extend(["", "## Screenshots", ""])
        for shot in self.screenshots:
            markdown.append("- " + Path(shot["file"]).name)
        md_file.write_text("\n".join(markdown) + "\n", encoding="utf-8")
        return {"status": summary["status"], "checks_passed": passed,
                "checks_failed": summary["checks_failed"], "json": str(json_file),
                "markdown": str(md_file), "screenshots": len(self.screenshots)}


class QAService:
    """Narrow MCP tool dispatcher. Backend never receives arbitrary command paths."""

    def __init__(self, config: Config, backend: Any) -> None:
        self.config = config
        self.backend = backend
        self.evidence = Evidence(config.output)

    def _needs_input(self) -> None:
        if not self.config.allow_input:
            raise QAError("Input is disabled: set AI_STORY_QA_ALLOW_INPUT=1 explicitly in the local MCP config")
        if self.evidence.run_dir is None:
            raise QAError("Call qa_begin before any game input, so every action is logged")

    @staticmethod
    def _bounded(value: Any, lower: int, upper: int, title: str) -> int:
        if type(value) is not int or not lower <= value <= upper:
            raise QAError(f"{title} must be an integer from {lower} to {upper}")
        return value

    def call(self, name: str, args: dict[str, Any]) -> tuple[dict[str, Any], bytes | None]:
        if not isinstance(args, dict):
            raise QAError("Tool arguments must be a JSON object")
        if name == "qa_status":
            return ({"platform": platform.system(), "app_path": str(self.config.exe) if self.config.exe else None,
                     "input_enabled": self.config.allow_input, "output_directory": str(self.config.output),
                     "backend": self.backend.status()}, None)
        if name == "qa_begin":
            return self.evidence.begin(str(args.get("name", ""))), None
        if name == "qa_launch":
            self._needs_input()
            value = self.backend.launch()
            self.evidence.action(name, {"pid": value.get("pid")})
            return value, None
        if name == "qa_attach":
            pid = args.get("pid")
            if pid is not None:
                self._bounded(pid, 1, 2**31-1, "pid")
            return self.backend.attach(pid=pid), None
        if name == "qa_close":
            self._needs_input()
            value = self.backend.close()
            self.evidence.action(name, {"pid": value.get("pid"), "graceful": True})
            return value, None
        if name == "qa_tree":
            max_nodes = self._bounded(args.get("max_nodes", 160), 1, 300, "max_nodes")
            max_depth = self._bounded(args.get("max_depth", 9), 1, 20, "max_depth")
            return self.backend.tree(max_nodes=max_nodes, max_depth=max_depth), None
        if name == "qa_click":
            self._needs_input()
            selector = self._selector(args)
            value = self.backend.click(selector)
            self.evidence.action(name, {"selector": selector})
            return value, None
        if name == "qa_click_xy":
            self._needs_input()
            x = self._bounded(args.get("x"), 0, 10000, "x")
            y = self._bounded(args.get("y"), 0, 10000, "y")
            value = self.backend.click_xy(x, y)
            self.evidence.action(name, {"x": x, "y": y})
            return value, None
        if name == "qa_type_focused":
            self._needs_input()
            content = args.get("text")
            if not isinstance(content, str) or len(content) > 3000:
                raise QAError("text must be a string of at most 3000 characters")
            value = self.backend.type_focused(content)
            self.evidence.action(name, {"characters": len(content)})
            return value, None
        if name == "qa_set_text":
            self._needs_input()
            selector = self._selector(args)
            content = args.get("text")
            if not isinstance(content, str) or len(content) > 3000:
                raise QAError("text must be a string of at most 3000 characters")
            value = self.backend.set_text(selector, content)
            self.evidence.action(name, {"selector": selector, "characters": len(content)})
            return value, None
        if name == "qa_press":
            self._needs_input()
            key = str(args.get("key", "")).upper().strip()
            allowed = {"ENTER", "ESC", "TAB", "SPACE", "UP", "DOWN", "LEFT", "RIGHT",
                       "PAGEUP", "PAGEDOWN", "HOME", "END", "CTRL+A", "CTRL+O", "CTRL+S", "BACKSPACE"}
            if key not in allowed:
                raise QAError("Key is not in the bounded QA navigation allowlist")
            value = self.backend.press(key)
            self.evidence.action(name, {"key": key})
            return value, None
        if name == "qa_scroll":
            self._needs_input()
            steps = self._bounded(args.get("steps", 2), 1, 8, "steps")
            direction = args.get("direction", "down")
            if direction not in ("up", "down"):
                raise QAError("direction must be up or down")
            value = self.backend.scroll(direction, steps)
            self.evidence.action(name, {"direction": direction, "steps": steps})
            return value, None
        if name == "qa_screenshot":
            label = str(args.get("label", "screenshot"))[:120]
            png = self.backend.screenshot()
            meta = self.evidence.screenshot(label, png)
            return meta, png
        if name == "qa_assert":
            text = args.get("text_contains")
            automation_id = args.get("automation_id")
            if not (isinstance(text, str) and text or isinstance(automation_id, str) and automation_id):
                raise QAError("Supply text_contains or automation_id")
            present = args.get("present", True)
            enabled = args.get("enabled")
            if type(present) is not bool or enabled is not None and type(enabled) is not bool:
                raise QAError("present and enabled must be booleans")
            snapshot = self.backend.tree(max_nodes=300, max_depth=20)
            found = [item for item in snapshot["nodes"]
                     if (text is None or text.casefold() in item["name"].casefold())
                     and (automation_id is None or automation_id == item["automation_id"])
                     and (enabled is None or enabled == item["enabled"])]
            passed = bool(found) == present
            desc = f"{'Present' if present else 'Absent'}: " + (f"text contains {text!r}" if text else f"id={automation_id!r}")
            if enabled is not None:
                desc += f"; enabled={enabled}"
            result = self.evidence.check(desc, passed, found)
            result["matches"] = len(found)
            result["tree_truncated"] = snapshot.get("truncated", False)
            if (result["tree_truncated"] or snapshot.get("accessibility_empty", False)) and not found:
                result["inconclusive"] = True
                result["passed"] = False
                self.evidence.checks[-1]["passed"] = False
            return result, None
        if name == "qa_wait_text":
            text = args.get("text_contains")
            if not isinstance(text, str) or not text or len(text) > 160:
                raise QAError("Provide text_contains (1..160 characters)")
            seconds = args.get("timeout_seconds", 10)
            self._bounded(seconds, 1, 20, "timeout_seconds")
            end = time.monotonic() + seconds
            while True:
                snap = self.backend.tree(max_nodes=300, max_depth=20)
                matches = [x for x in snap["nodes"] if text.casefold() in x["name"].casefold()]
                if matches:
                    return {"found": True, "matches": matches[:8]}, None
                if time.monotonic() >= end:
                    return {"found": False, "text_contains": text, "tree_truncated": snap.get("truncated", False)}, None
                time.sleep(0.4)
        if name == "qa_note":
            scenario = args.get("scenario")
            reason = args.get("reason")
            status = args.get("status")
            if any(type(value) is not str for value in (scenario, reason, status)):
                raise QAError("scenario, status and reason must be strings")
            return self.evidence.note(scenario, status, reason), None
        if name == "qa_report":
            return self.evidence.report(), None
        raise QAError("Unknown tool name: " + name)

    @staticmethod
    def _selector(args: dict[str, Any]) -> dict[str, str]:
        allowed = ("node_id", "automation_id", "name")
        result = {k: args[k] for k in allowed if k in args and args[k] is not None}
        if len(result) != 1 or any(not isinstance(v, str) or not v or len(v) > 300 for v in result.values()):
            raise QAError("Supply exactly one nonempty selector: node_id, automation_id, or exact name")
        return result