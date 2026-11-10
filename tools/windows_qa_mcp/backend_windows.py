"""Bounded Windows UI Automation adapter for AI Story RPG portable EXE.

The adapter never runs shell commands and only interacts with windows owned
by ai_story_reader.exe. Windows-only imports are deferred for Linux CI.
"""
from __future__ import annotations

import io
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Any

from .core import Config, QAError

APP_EXE = "ai_story_reader.exe"


def matches_executable(actual: str | Path, configured: Path | None) -> bool:
    path = Path(actual)
    if path.name.casefold() != APP_EXE:
        return False
    if configured is None:
        return False  # A process name alone is never an authorization boundary.
    # win32 path comparisons are case-insensitive. Do not allow prefix matches.
    return os.path.normcase(str(path.resolve())).casefold() == os.path.normcase(str(configured.resolve())).casefold()


def validate_relative_point(x: int, y: int, width: int, height: int) -> None:
    if type(x) is not int or type(y) is not int or x < 0 or y < 0 or x >= width or y >= height:
        raise QAError(f"Click must be inside the application window (0..{width-1}, 0..{height-1})")


class WindowsBackend:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.pid: int | None = None
        self._node_cache: dict[str, Any] = {}
        self._last_image: tuple[int, int, int, int] | None = None

    def _windows(self) -> None:
        if os.name != "nt":
            raise QAError("UI automation requires interactive Windows, not the GitHub Linux runner")

    @staticmethod
    def _modules():
        try:
            import psutil
            from pywinauto import Desktop, mouse, keyboard
            from PIL import ImageGrab
        except ImportError as exc:
            raise QAError("Install Windows MCP dependencies: python -m pip install -r tools/windows_qa_mcp/requirements.txt") from exc
        return psutil, Desktop, mouse, keyboard, ImageGrab

    def _candidates(self) -> list[int]:
        self._windows()
        if self.config.exe is None:
            raise QAError("Configure AI_STORY_QA_EXE with the full path to ai_story_reader.exe")
        psutil, *_ = self._modules()
        result = []
        for proc in psutil.process_iter(["pid", "name", "exe"]):
            try:
                if proc.info["exe"] and matches_executable(proc.info["exe"], self.config.exe):
                    result.append(proc.info["pid"])
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        return sorted(result)

    def _verify_pid(self, pid: int) -> None:
        psutil, *_ = self._modules()
        try:
            actual = psutil.Process(pid).exe()
        except (psutil.NoSuchProcess, psutil.AccessDenied) as exc:
            raise QAError("Cannot inspect the specified process") from exc
        if not matches_executable(actual, self.config.exe):
            raise QAError("Refusing to attach to any process other than the configured AI Story RPG executable")

    def status(self) -> dict[str, Any]:
        if os.name != "nt":
            return {"available": False, "reason": "Windows desktop required"}
        try:
            candidates = self._candidates()
            return {"available": True, "matching_pids": candidates, "attached_pid": self.pid}
        except QAError as exc:
            return {"available": False, "reason": str(exc)}

    def attach(self, pid: int | None = None) -> dict[str, Any]:
        candidates = self._candidates()
        if pid is None:
            if not candidates:
                raise QAError("AI Story RPG is not running; call qa_launch or start ai_story_reader.exe manually")
            if len(candidates) != 1:
                raise QAError("More than one game process is open; call qa_attach with the intended PID")
            pid = candidates[0]
        if pid not in candidates:
            raise QAError("PID is not a trusted AI Story RPG process")
        self._verify_pid(pid)
        self.pid = pid
        self._node_cache.clear()
        self._last_image = None
        window = self._window()
        rect = window.rectangle()
        return {"pid": pid, "title": window.window_text(), "width": rect.width(), "height": rect.height()}

    def close(self) -> dict[str, Any]:
        """Request a normal WM_CLOSE for the verified game window; never kill processes."""
        window = self._window()
        pid = self.pid
        try:
            window.close()
        except Exception as exc:
            raise QAError("Graceful game window close failed") from exc
        self._node_cache.clear()
        self._last_image = None
        self.pid = None
        return {"pid": pid, "close_requested": True, "forced_kill": False}

    def launch(self) -> dict[str, Any]:
        self._windows()
        exe = self.config.exe
        if exe is None or not matches_executable(exe, exe):
            raise QAError("Configure AI_STORY_QA_EXE with the absolute path to ai_story_reader.exe")
        if not exe.is_file():
            raise QAError("Configured EXE does not exist")
        if not (exe.parent / "data").is_dir() or not (exe.parent / "flutter_windows.dll").is_file():
            raise QAError("Portable game is incomplete: keep EXE, Flutter DLL and data together")
        candidates = self._candidates()
        if len(candidates) == 1:
            return {"already_running": True, **self.attach(candidates[0])}
        if candidates:
            raise QAError("Multiple existing game processes; attach to a specific PID")
        # The game does not need the MCP client's LLM tokens or passwords.
        safe_env = {key: value for key, value in os.environ.items()
                    if not re.search(r"(TOKEN|API_KEY|SECRET|PASSWORD|CREDENTIAL|AUTH)", key, re.I)}
        process = subprocess.Popen([str(exe)], cwd=str(exe.parent), shell=False,
                                   env=safe_env, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(20):
            time.sleep(0.35)
            try:
                return {"already_running": False, **self.attach(process.pid)}
            except QAError:
                if process.poll() is not None:
                    raise QAError(f"Game process exited during launch: {process.returncode}")
        raise QAError("Game started but no visible main window appeared in 7 seconds; retry qa_attach")

    def _window(self):
        self._windows()
        if self.pid is None:
            raise QAError("Call qa_attach or qa_launch first")
        self._verify_pid(self.pid)
        _, Desktop, *_ = self._modules()
        try:
            windows = [w for w in Desktop(backend="uia").windows(process=self.pid)
                       if w.is_visible() and w.element_info.process_id == self.pid]
        except Exception as exc:
            raise QAError("Unable to enumerate UI Automation windows; check desktop session access") from exc
        if not windows:
            raise QAError("No visible game window (is the app minimized or on another desktop?)")
        # Prefer a visible native modal dialog (file pickers), then the root.
        # Dialog controls are frequently outside the Flutter accessibility tree.
        import win32gui
        foreground = win32gui.GetForegroundWindow()
        for item in windows:
            if item.handle == foreground:
                return item
        dialogs = [item for item in windows if item.class_name() == "#32770"]
        if dialogs:
            return dialogs[0]
        return max(windows, key=lambda w: ("Живая книга" in w.window_text(),
                                            w.rectangle().width() * w.rectangle().height()))

    def _tree_nodes(self, max_nodes: int, max_depth: int) -> dict[str, Any]:
        window = self._window()
        stack = [(window, 0)]
        nodes: list[dict[str, Any]] = []
        cache: dict[str, Any] = {}
        truncated = False
        while stack:
            item, depth = stack.pop()
            try:
                if item.element_info.process_id not in (self.pid, None):
                    continue
                rect = item.rectangle()
                node_id = f"n{len(nodes)+1:04d}"
                name = str(item.element_info.name or "")[:300]
                automation_id = str(item.element_info.automation_id or "")[:200]
                nodes.append({"node_id": node_id, "name": name,
                              "automation_id": automation_id,
                              "control_type": str(item.element_info.control_type or ""),
                              "enabled": bool(item.is_enabled()),
                              "visible": bool(item.is_visible()),
                              "bounds": [rect.left, rect.top, rect.right, rect.bottom],
                              "depth": depth})
                cache[node_id] = item
                if depth >= max_depth:
                    if item.children():
                        truncated = True
                else:
                    children = item.children()
                    stack.extend((child, depth + 1) for child in reversed(children))
            except Exception:
                # A transient / virtualized UI element may disappear between calls.
                continue
            if len(nodes) >= max_nodes:
                truncated = truncated or bool(stack)
                break
        self._node_cache = cache
        bounds = window.rectangle()
        return {"pid": self.pid, "title": window.window_text(),
                "window_bounds": [bounds.left, bounds.top, bounds.right, bounds.bottom],
                "nodes": nodes, "truncated": truncated, "accessibility_empty": len(nodes) <= 1}

    def tree(self, max_nodes: int = 160, max_depth: int = 9) -> dict[str, Any]:
        return self._tree_nodes(max_nodes, max_depth)

    def _element(self, selector: dict[str, str]):
        if "node_id" in selector:
            element = self._node_cache.get(selector["node_id"])
            if element is None:
                raise QAError("Unknown or stale node_id; call qa_tree and choose a fresh ID")
        else:
            snapshot = self._tree_nodes(500, 20)
            key, value = next(iter(selector.items()))
            matches = [self._node_cache[node["node_id"]] for node in snapshot["nodes"]
                       if node.get(key) == value]
            if not matches:
                raise QAError(f"UIA element not found by exact {key}={value!r}; inspect qa_tree or use qa_click_xy")
            if len(matches) != 1:
                raise QAError(f"Ambiguous {key}={value!r} matches {len(matches)} controls; use node_id")
            element = matches[0]
        try:
            rect = element.rectangle()
            win = self._window().rectangle()
            if element.element_info.process_id != self.pid or not element.is_visible() or not element.is_enabled():
                raise QAError("Selected element is hidden, disabled or outside the game process")
            if rect.width() <= 0 or rect.height() <= 0 or rect.right <= win.left or rect.left >= win.right or rect.bottom <= win.top or rect.top >= win.bottom:
                raise QAError("Selected control is outside the visible application window")
        except QAError:
            raise
        except Exception as exc:
            raise QAError("UIA node is stale; call qa_tree again") from exc
        return element

    def _focus(self) -> None:
        try:
            self._window().set_focus()
        except Exception as exc:
            raise QAError("Could not activate the game window; allow desktop interaction") from exc

    def click(self, selector: dict[str, str]) -> dict[str, Any]:
        self._focus()
        control = self._element(selector)
        try:
            control.click_input()
        except Exception as exc:
            raise QAError("UI Automation click failed; use bounded qa_click_xy as fallback") from exc
        return {"clicked": selector}

    def click_xy(self, x: int, y: int) -> dict[str, Any]:
        window = self._window()
        rect = window.rectangle()
        validate_relative_point(x, y, rect.width(), rect.height())
        if self._last_image is None:
            raise QAError("Call qa_screenshot first; coordinates are relative to its returned image")
        image_width, image_height, old_width, old_height = self._last_image
        if (rect.width(), rect.height()) != (old_width, old_height):
            raise QAError("Window size changed after screenshot; take a new screenshot")
        validate_relative_point(x, y, image_width, image_height)
        actual_x = int((x + 0.5) * rect.width() / image_width)
        actual_y = int((y + 0.5) * rect.height() / image_height)
        self._focus()
        _, _, mouse, *_ = self._modules()
        px, py = rect.left + actual_x, rect.top + actual_y
        mouse.click(button="left", coords=(px, py))
        return {"clicked_image": [x, y], "clicked_window": [actual_x, actual_y]}

    def set_text(self, selector: dict[str, str], value: str) -> dict[str, Any]:
        if any(ord(char) < 32 and char not in "\t" for char in value):
            raise QAError("Text contains control characters")
        self._focus()
        control = self._element(selector)
        if str(control.element_info.control_type) not in ("Edit", "ComboBox", "Document"):
            raise QAError("qa_set_text requires an editable game control; use qa_click_xy + qa_type_focused for Flutter custom inputs")
        _, _, _, keyboard, _ = self._modules()
        try:
            control.click_input()
            keyboard.send_keys("^a")
            # pywinauto reserves braces for key commands. vk_packet handles Unicode.
            escaped = value.replace("{", "{{}").replace("}", "{}}")
            keyboard.send_keys(escaped, with_spaces=True, with_tabs=True, vk_packet=True)
        except Exception as exc:
            raise QAError("Could not type into selected control; check focus / UI Automation") from exc
        return {"typed_characters": len(value), "selector": selector}

    def type_focused(self, value: str) -> dict[str, Any]:
        if any(ord(char) < 32 and char not in "\t" for char in value):
            raise QAError("Text contains control characters")
        self._focus()
        _, _, _, keyboard, _ = self._modules()
        escaped = value.replace("{", "{{}").replace("}", "{}}")
        keyboard.send_keys(escaped, with_spaces=True, with_tabs=True, vk_packet=True)
        return {"typed_characters": len(value)}

    def press(self, key: str) -> dict[str, Any]:
        self._focus()
        _, _, _, keyboard, _ = self._modules()
        codes = {"ENTER": "{ENTER}", "ESC": "{ESC}", "TAB": "{TAB}",
                 "SPACE": "{SPACE}", "UP": "{UP}", "DOWN": "{DOWN}",
                 "LEFT": "{LEFT}", "RIGHT": "{RIGHT}",
                 "PAGEUP": "{PGUP}", "PAGEDOWN": "{PGDN}",
                 "HOME": "{HOME}", "END": "{END}", "CTRL+A": "^a",
                 "CTRL+O": "^o", "CTRL+S": "^s", "BACKSPACE": "{BACKSPACE}"}
        keyboard.send_keys(codes[key])
        return {"pressed": key}

    def scroll(self, direction: str, steps: int) -> dict[str, Any]:
        self._focus()
        rect = self._window().rectangle()
        _, _, mouse, *_ = self._modules()
        mouse.scroll(coords=(rect.left + rect.width() // 2,
                             rect.top + (3 * rect.height()) // 4),
                     wheel_dist=steps if direction == "up" else -steps)
        return {"direction": direction, "steps": steps}

    def screenshot(self) -> bytes:
        window = self._window()
        rect = window.rectangle()
        if rect.width() <= 0 or rect.height() <= 0:
            raise QAError("Window has no visible size")
        _, _, _, _, ImageGrab = self._modules()
        try:
            # Activate the verified game window before grabbing its rectangle.
            # Desktop notifications/topmost windows can still obscure it;
            # agents must inspect screenshots rather than infer hidden UI state.
            self._focus()
            im = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom), all_screens=True)
            original = im.size
            im.thumbnail((1600, 1000))
            self._last_image = (im.width, im.height, original[0], original[1])
            stream = io.BytesIO()
            im.convert("RGB").save(stream, format="PNG", optimize=True)
            return stream.getvalue()
        except Exception as exc:
            raise QAError("Window screenshot failed; desktop may be locked or running without a display") from exc