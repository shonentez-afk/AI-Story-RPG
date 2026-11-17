"""Read only Windows Application Error events for ONE configured RPG executable.

Does not invoke PowerShell or read the message text of unrelated events. Only
EventID 1000 with a verified exact EXE path is returned. WER 1001 records are
excluded because they need not carry a trustworthy application path.
"""
from __future__ import annotations

import ntpath
import os
import re
import time
from pathlib import Path
from typing import Any

EXE_NAME = 'ai_story_reader.exe'


def _norm_win(path: str) -> str:
    return ntpath.normcase(ntpath.normpath(path.strip().strip('"')))


def extract_app_crash(event: Any, configured_exe: Path) -> dict[str, str] | None:
    """Parse only a Windows Application Error 1000 matching exact full path."""
    try:
        if getattr(event, 'SourceName', '') != 'Application Error':
            return None
        if (int(event.EventID) & 0xffff) != 1000:
            return None
        parts = [str(x or '') for x in (event.StringInserts or [])]
        if len(parts) < 12 or ntpath.basename(parts[0]).casefold() != EXE_NAME:
            return None
        if _norm_win(parts[10]) != _norm_win(str(configured_exe)):
            return None
        code = parts[6].strip()
        if not re.fullmatch(r'0x[0-9a-fA-F]{1,16}', code):
            code = 'unknown'
        return {
            'event_id': '1000',
            'event_time_local': str(getattr(event, 'TimeGenerated', 'unknown'))[:48],
            'application': EXE_NAME,
            'faulting_module': ntpath.basename(parts[3].strip())[:96],
            'exception_code': code,
            'path_verified': 'true',
        }
    except (AttributeError, TypeError, ValueError):
        return None


def recent_app_crashes(configured_exe: Path | None, hours: int = 24,
                       max_events: int = 20) -> dict[str, Any]:
    if os.name != 'nt':
        return {'available': False, 'reason': 'Windows Application Event Log required', 'events': []}
    if configured_exe is None or configured_exe.name.casefold() != EXE_NAME:
        return {'available': False, 'reason': 'Exact game EXE must be configured', 'events': []}
    import win32evtlog  # pywin32, installed by Windows MCP dependency
    try:
        log = win32evtlog.OpenEventLog(None, 'Application')
    except Exception:
        return {'available': False, 'reason': 'Cannot read Windows Application event log', 'events': []}
    scanned = 0
    entries: list[dict[str, str]] = []
    scan_limit = 5000
    end_reached = False
    cutoff = time.time() - hours * 3600
    try:
        flags = win32evtlog.EVENTLOG_BACKWARDS_READ | win32evtlog.EVENTLOG_SEQUENTIAL_READ
        while scanned < scan_limit and len(entries) < max_events and not end_reached:
            block = win32evtlog.ReadEventLog(log, flags, 0)
            if not block:
                end_reached = True
                break
            for item in block:
                scanned += 1
                stamp = getattr(item, 'TimeGenerated', None)
                try:
                    epoch = float(stamp.timestamp()) if hasattr(stamp, 'timestamp') else float(stamp)
                    if epoch < cutoff:
                        end_reached = True
                        break
                except (ValueError, TypeError, OverflowError):
                    # Still bounded by scan_limit; unknown timestamp is not evidence.
                    pass
                crash = extract_app_crash(item, configured_exe)
                if crash is not None:
                    entries.append(crash)
                    if len(entries) >= max_events:
                        break
                if scanned >= scan_limit:
                    break
        return {
            'available': True, 'events': entries,
            'hours_requested': hours, 'records_scanned': scanned,
            'truncated': scanned >= scan_limit or (len(entries) >= max_events and not end_reached),
            'source': 'Windows Application Error / EventID 1000',
            'path_match_required': True,
        }
    except Exception:
        return {'available': False, 'reason': 'Windows Application log read interrupted',
                'events': entries, 'records_scanned': scanned}
    finally:
        win32evtlog.CloseEventLog(log)