"""Absolute-path STDIO launcher for GigaCode Desktop.

The desktop host may ignore cwd or start the server from an unrelated folder.
Run this file directly: python.exe -u C:\\...\\tools\\windows_qa_mcp\\launch_gigacode.py
Never emit diagnostic text to stdout during a normal MCP session.
"""
from __future__ import annotations

import os
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def _report_failure() -> None:
    """Keep startup failures locally inspectable when GigaCode hides stderr."""
    details = traceback.format_exc()
    try:
        root = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "AIStoryRPG-QA"
        root.mkdir(parents=True, exist_ok=True)
        with (root / "mcp-startup-errors.log").open("a", encoding="utf-8") as stream:
            stream.write("\n--- " + datetime.now(timezone.utc).isoformat() + " ---\n")
            stream.write(details[:16000] + "\n")
    except OSError:
        pass
    print(details, file=sys.stderr, flush=True)


def main() -> int:
    # Direct script invocation sets sys.path[0] to tools/windows_qa_mcp,
    # NOT to the project root. Importing tools.* must work from any cwd.
    root = str(REPO_ROOT)
    if root not in sys.path:
        sys.path.insert(0, root)
    try:
        from tools.windows_qa_mcp.server import main as serve
        return serve()
    except Exception:
        _report_failure()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())