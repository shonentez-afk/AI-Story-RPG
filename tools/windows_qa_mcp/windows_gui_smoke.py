"""Best-effort real Windows EXE GUI smoke on a disposable GitHub Actions VM.

Never call this a pass if GitHub's service session cannot show a window.
Windows UIA/screenshots and app-crash event evidence are recorded in a QA
report; output is separate from deterministic Flutter widget tests.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from .backend_windows import WindowsBackend
from .core import Config, QAError, QAService


def main() -> int:
    config = Config.from_env()
    service = QAService(config, WindowsBackend(config))
    started, close_requested = False, False
    try:
        service.call('qa_begin', {'name': 'github-windows-real-ui-smoke'})
        if not config.allow_input:
            service.call('qa_note', {'scenario': 'Windows EXE launch', 'status': 'BLOCKED',
                                     'reason': 'Runner did not explicitly opt in to input'})
            return _report(service)
        try:
            service.call('qa_launch', {})
            started = True
            time.sleep(0.4)
            before, _ = service.call('qa_status', {})
            matches = before.get('backend', {}).get('matching_pids', [])
            if not matches:
                raise QAError('Application exited before first screenshot')
            ui, _ = service.call('qa_tree', {'max_nodes': 300, 'max_depth': 15})
            try:
                shot, _ = service.call('qa_screenshot', {'label': 'home-window'})
                print('Windows EXE screenshot captured: ' + str(Path(shot['file']).name),
                      file=sys.stderr, flush=True)
            except Exception as exc:
                service.call('qa_note', {
                    'scenario': 'Windows desktop screenshot', 'status': 'INCONCLUSIVE',
                    'reason': 'Screenshot not available: ' + type(exc).__name__})
            names = [node['name'] for node in ui['nodes']]
            if any('Живая книга' in name for name in names):
                service.call('qa_assert', {'text_contains': 'Живая книга'})
            elif ui.get('accessibility_empty') or ui.get('truncated'):
                service.call('qa_note', {
                    'scenario': 'Flutter UI accessibility', 'status': 'INCONCLUSIVE',
                    'reason': 'UI Automation tree empty or truncated in GitHub runner'})
            else:
                service.call('qa_note', {
                    'scenario': 'Flutter UI accessibility', 'status': 'INCONCLUSIVE',
                    'reason': 'Game process alive, home title not exposed through UIA'})
        except Exception as exc:
            service.call('qa_note', {
                'scenario': 'Real Windows EXE GUI', 'status': 'BLOCKED',
                'reason': 'Interactive GUI not proven: ' + type(exc).__name__ +
                          ': ' + str(exc)[:220]})
        finally:
            try:
                if started:
                    service.call('qa_crash_events', {'hours': 1, 'max_events': 10})
            except Exception:
                service.call('qa_note', {
                    'scenario': 'Windows Application Error events',
                    'status': 'INCONCLUSIVE', 'reason': 'Event log unavailable'})
            try:
                if started:
                    service.call('qa_close', {})
                    close_requested = True
            except Exception:
                service.call('qa_note', {
                    'scenario': 'Normal GUI close', 'status': 'INCONCLUSIVE',
                    'reason': 'Could not verify graceful close'})
        return _report(service, started, close_requested)
    except Exception as exc:
        print('Windows GUI smoke setup failed: ' + repr(exc), file=sys.stderr)
        return 1


def _report(service: QAService, launched: bool = False,
            close_requested: bool = False) -> int:
    report, _ = service.call('qa_report', {})
    print(json.dumps({'qa_report': report, 'launch_attempted': launched,
                      'close_requested': close_requested}, ensure_ascii=False))
    # BLOCKED is a legitimate conclusion in service sessions, not PASS.
    # Job success means evidence was generated, never that GUI passed.
    return 0


if __name__ == '__main__':
    raise SystemExit(main())