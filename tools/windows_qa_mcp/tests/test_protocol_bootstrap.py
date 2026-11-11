"""Regression checks for the exact GigaCode Desktop STDIO startup mechanism.

These tests run without mcp/pywinauto installed. A separate protocol smoke
uses the real MCP v1 client when dependencies have been installed in CI.
"""
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.windows_qa_mcp.protocol_smoke import EXPECTED_TOOLS

ROOT = Path(__file__).resolve().parents[1]


class DesktopBootstrapTests(unittest.TestCase):
    def test_absolute_launcher_imports_from_an_unrelated_working_directory(self):
        with tempfile.TemporaryDirectory(prefix="unrelated-mcp-cwd-") as cwd:
            run = subprocess.run(
                [sys.executable, str(ROOT / "launch_gigacode.py"), "--invalid"],
                cwd=cwd, capture_output=True, text=True, timeout=10, check=False,
            )
        self.assertEqual(run.returncode, 2, run.stderr)
        self.assertIn("Usage:", run.stderr)
        self.assertEqual(run.stdout, "", "Normal MCP launches must not emit non-JSON stdout")
        self.assertNotIn("ModuleNotFoundError", run.stderr)

    def test_all_registered_tools_have_exact_protocol_expected_names(self):
        server = (ROOT / "server.py").read_text(encoding="utf-8")
        tool_names = set(re.findall(r"@mcp\.tool\(\)\s*\n\s*def\s+(qa_\w+)\s*\(", server))
        self.assertEqual(tool_names, EXPECTED_TOOLS)
        self.assertEqual(len(tool_names), 17)

    def test_installer_uses_absolute_script_path_not_cwd_sensitive_module(self):
        script = (ROOT / "setup_gigacode_desktop.ps1").read_text(encoding="utf-8")
        self.assertIn("launch_gigacode.py", script)
        self.assertIn("protocol_smoke.py", script)
        self.assertIn("args    = @('-u', $bootstrap)", script)
        self.assertNotIn("args    = @('-m', 'tools.windows_qa_mcp.server')", script)
        self.assertIn("sys.version_info >= (3, 12)", script)

    def test_mcp_dispatch_helper_does_not_collide_with_tool_name_argument(self):
        # A helper named result(name, **kwargs) crashed qa_begin(name=...).
        server = (ROOT / "server.py").read_text(encoding="utf-8")
        self.assertIn('def result(tool_name: str, **kwargs)', server)
        self.assertNotIn('def result(name: str, **kwargs)', server)

    def test_mcp_tool_signature_does_not_reference_locally_imported_types(self):
        # Windows CI caught MCP 1.30 InvalidSignature on this exact annotation.
        server = (ROOT / "server.py").read_text(encoding="utf-8")
        self.assertIn('def qa_screenshot(label: str = "screen"):', server)
        self.assertNotIn('-> list[TextContent | ImageContent]', server)

    def test_protocol_smoke_tests_real_handshake_and_not_just_sdk_import(self):
        smoke = (ROOT / "protocol_smoke.py").read_text(encoding="utf-8")
        for snippet in ("session.initialize()", "session.list_tools()",
                        'session.call_tool("qa_status"',
                        'session.call_tool("qa_begin"',
                        'session.call_tool("qa_report"',
                        "cwd=str(unrelated)", '"AI_STORY_QA_ALLOW_INPUT": "0"'):
            with self.subTest(snippet=snippet):
                self.assertIn(snippet, smoke)


if __name__ == "__main__":
    unittest.main()