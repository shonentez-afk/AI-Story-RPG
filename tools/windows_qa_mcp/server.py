"""GigaCode Desktop Local MCP (STDIO) entrypoint; start from repository root.

Run: python -m tools.windows_qa_mcp.server
Preflight: python -m tools.windows_qa_mcp.server --self-check
"""
from __future__ import annotations

import json
import os
import sys

from .backend_windows import WindowsBackend
from .core import Config, QAError, QAService


def _build():
    # Pin SDK 1.x: FastMCP + Image are the supported 1.x interfaces.
    from mcp.server.fastmcp import FastMCP, Image
    from mcp.types import TextContent, ImageContent

    config = Config.from_env()
    service = QAService(config, WindowsBackend(config))
    mcp = FastMCP("AI Story RPG Windows QA (GigaCode Desktop)")

    def result(tool_name: str, **kwargs) -> str:
        # Avoid collision with real tool arguments called 'name'.
        value, _ = service.call(tool_name, kwargs)
        return json.dumps(value, ensure_ascii=False)

    @mcp.tool()
    def qa_status() -> str:
        """Read-only preflight: target EXE, process IDs, input permission and evidence directory."""
        return result("qa_status")

    @mcp.tool()
    def qa_begin(name: str) -> str:
        """Start an isolated QA report (must precede assertions/screenshots). No app changes."""
        return result("qa_begin", name=name)

    @mcp.tool()
    def qa_attach(pid: int | None = None) -> str:
        """Attach to the running ai_story_reader.exe; reject unrelated processes."""
        return result("qa_attach", pid=pid)

    @mcp.tool()
    def qa_launch() -> str:
        """Launch only AI_STORY_QA_EXE (requires AI_STORY_QA_ALLOW_INPUT=1)."""
        return result("qa_launch")

    @mcp.tool()
    def qa_close() -> str:
        """Ask only the attached game window to close normally; no process kill (input opt-in required)."""
        return result("qa_close")

    @mcp.tool()
    def qa_tree(max_nodes: int = 160, max_depth: int = 9) -> str:
        """Inspect ONLY the game window's UI Automation tree. May be sparse in Flutter release builds."""
        return result("qa_tree", max_nodes=max_nodes, max_depth=max_depth)

    # Do not annotate with locally imported TextContent/ImageContent: MCP v1.30
    # resolves annotations at module scope and aborts tool registration.
    @mcp.tool()
    def qa_screenshot(label: str = "screen"):
        """Capture only the game window and save a PNG in the active QA run. Returns real image content."""
        value, png = service.call("qa_screenshot", {"label": label})
        if png is None:
            raise QAError("Screenshot backend did not return image bytes")
        image_size = service.backend._last_image
        value["image_size"] = list(image_size[:2]) if image_size else None
        value["window_size"] = list(image_size[2:]) if image_size else None
        text = TextContent(type="text", text=json.dumps(value, ensure_ascii=False))
        # Native MCP content blocks: GigaCode can show images if its model supports vision.
        return [text, Image(data=png, format="png").to_image_content()]

    @mcp.tool()
    def qa_click(name: str = "", automation_id: str = "", node_id: str = "") -> str:
        """Click an exact UIA selector in game. Supply ONE of name, automation_id, node_id."""
        data = {k: v for k, v in {"name": name, "automation_id": automation_id, "node_id": node_id}.items() if v}
        return result("qa_click", **data)

    @mcp.tool()
    def qa_click_xy(x: int, y: int) -> str:
        """Click coordinates INSIDE last screenshot, not desktop coords. UIA fallback only; input opt-in."""
        return result("qa_click_xy", x=x, y=y)

    @mcp.tool()
    def qa_set_text(text: str, name: str = "", automation_id: str = "", node_id: str = "") -> str:
        """Type up to 3000 chars in an exact game UIA element; never put secrets in QA tests."""
        data = {k: v for k, v in {"name": name, "automation_id": automation_id, "node_id": node_id}.items() if v}
        return result("qa_set_text", text=text, **data)

    @mcp.tool()
    def qa_type_focused(text: str) -> str:
        """Type into a game field focused by qa_click_xy, when Flutter UIA lacks editable nodes."""
        return result("qa_type_focused", text=text)

    @mcp.tool()
    def qa_press(key: str) -> str:
        """Send one allowlisted navigation key to game; no arbitrary shortcuts or shell commands."""
        return result("qa_press", key=key)

    @mcp.tool()
    def qa_scroll(direction: str = "down", steps: int = 2) -> str:
        """Scroll only the game window, by 1..8 wheel steps up or down."""
        return result("qa_scroll", direction=direction, steps=steps)

    @mcp.tool()
    def qa_wait_text(text_contains: str, timeout_seconds: int = 10) -> str:
        """Wait at most 20 seconds for visible accessibility text; not a screenshot OCR check."""
        return result("qa_wait_text", text_contains=text_contains, timeout_seconds=timeout_seconds)

    @mcp.tool()
    def qa_assert(text_contains: str | None = None, automation_id: str | None = None,
                  present: bool = True, enabled: bool | None = None) -> str:
        """Record PASS/FAIL UIA assertion; blank/truncated UIA cannot prove absence."""
        return result("qa_assert", text_contains=text_contains, automation_id=automation_id,
                      present=present, enabled=enabled)

    @mcp.tool()
    def qa_note(scenario: str, status: str, reason: str) -> str:
        """Record BLOCKED/INCONCLUSIVE/SKIPPED coverage; cannot falsely mark untested steps PASS."""
        return result("qa_note", scenario=scenario, status=status, reason=reason)

    @mcp.tool()
    def qa_report() -> str:
        """Write JSON + Markdown evidence report. No assertions -> NOT_TESTED, never PASS."""
        return result("qa_report")

    return mcp, service


def main() -> int:
    if sys.argv[1:] == ["--self-check"]:
        # Do not report "MCP OK" solely because `import mcp` succeeds.
        # Fully register all FastMCP tools and validate their exported names.
        import asyncio
        from .protocol_smoke import EXPECTED_TOOLS
        config = Config.from_env()
        details = {"python": sys.executable, "platform": os.name,
                   "app_exe": str(config.exe) if config.exe else None,
                   "output": str(config.output), "input_enabled": config.allow_input}
        try:
            from importlib.metadata import version
            details["mcp_sdk_version"] = version("mcp")
            registered_mcp, _ = _build()
            exported = {t.name for t in asyncio.run(registered_mcp.list_tools())}
            details["registered_tool_count"] = len(exported)
            details["registered_tools"] = sorted(exported)
            if exported != EXPECTED_TOOLS:
                raise RuntimeError("MCP tool registration mismatch")
            details["status"] = "OK"
        except Exception as exc:
            details["status"] = "ERROR"
            details["error"] = repr(exc)
        print(json.dumps(details, ensure_ascii=False, indent=2))
        return 0 if details["status"] == "OK" else 1
    if sys.argv[1:]:
        print("Usage: python -m tools.windows_qa_mcp.server [--self-check]", file=sys.stderr)
        return 2
    # No print() on stdout: it carries the MCP JSON-RPC transport.
    mcp, _ = _build()
    mcp.run(transport="stdio")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())