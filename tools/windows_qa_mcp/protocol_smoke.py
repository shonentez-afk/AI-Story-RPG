"""Real MCP STDIO handshake smoke test, independent of GigaCode and cwd.

Run: python tools/windows_qa_mcp/protocol_smoke.py
Starts the actual 17-tool server as a subprocess from an unrelated directory,
performs initialize, tools/list, qa_status, qa_begin, qa_report, and exits.
No game GUI or user saves are touched.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path

EXPECTED_TOOLS = frozenset({
    "qa_status", "qa_begin", "qa_attach", "qa_launch", "qa_close",
    "qa_tree", "qa_screenshot", "qa_click", "qa_click_xy", "qa_set_text",
    "qa_type_focused", "qa_press", "qa_scroll", "qa_wait_text",
    "qa_assert", "qa_note", "qa_report",
})


def _text_result(response) -> dict:
    if getattr(response, "isError", False):
        raise AssertionError("MCP tool returned an error: " + str(response.content))
    for part in response.content:
        if getattr(part, "type", "") == "text":
            return json.loads(part.text)
    raise AssertionError("MCP response has no text content")


async def probe() -> dict:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    launcher = Path(__file__).resolve().parent / "launch_gigacode.py"
    with tempfile.TemporaryDirectory(prefix="mcp-stdio-cwd-") as temporary:
        unrelated = Path(temporary)
        # The MCP SDK supplies its own small allowlist of host environment
        # variables. Never pass unrelated model credentials to our test child.
        # No PYTHONPATH: imports must work through the absolute launcher.
        environment = {
            "AI_STORY_QA_EXE": str(unrelated / "ai_story_reader.exe"),
            "AI_STORY_QA_OUTPUT": str(unrelated / "evidence"),
            "AI_STORY_QA_ALLOW_INPUT": "0",
        }
        params = StdioServerParameters(
            command=sys.executable,
            args=["-u", str(launcher)],
            cwd=str(unrelated),
            env=environment,
        )
        async with stdio_client(params) as (read, write):
            async with ClientSession(read, write) as session:
                init = await session.initialize()
                names = {tool.name for tool in (await session.list_tools()).tools}
                if names != EXPECTED_TOOLS:
                    raise AssertionError(
                        "Expected exact 17 registered tools, got " + str(sorted(names))
                    )
                status = _text_result(await session.call_tool("qa_status", {}))
                if Path(status["app_path"]).name != "ai_story_reader.exe":
                    raise AssertionError("Configured game executable was not forwarded to MCP")
                if status.get("input_enabled") is not False:
                    raise AssertionError("Protocol smoke must use safe read-only mode")
                begin = _text_result(await session.call_tool("qa_begin", {"name": "stdio-smoke"}))
                report = _text_result(await session.call_tool("qa_report", {}))
                if report.get("status") != "NOT_TESTED":
                    raise AssertionError("Smoke run with no real UI assertions cannot be PASS")
                if not Path(report["json"]).is_file():
                    raise AssertionError("MCP report file was not created")
                return {
                    "status": "OK", "server": init.serverInfo.name,
                    "registered_tools": len(names), "tools": sorted(names),
                    "cwd_independent": True, "app_path_received": True,
                    "evidence_dir": str(Path(begin["directory"]).name),
                    "safe_report_status": report["status"],
                }


def main() -> int:
    try:
        result = asyncio.run(asyncio.wait_for(probe(), timeout=25))
        print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
        return 0
    except Exception as exc:
        print(json.dumps({"status": "ERROR", "error": str(exc)}, ensure_ascii=False),
              file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())