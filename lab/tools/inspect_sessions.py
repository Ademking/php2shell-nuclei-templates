#!/usr/bin/env python3
"""Print the newest php2shell test session file from the lab."""
from pathlib import Path

sessions = Path("/mnt/c/Users/ASUS/AppData/Local/Temp/opencode/php2shell-lab/sessions")
files = sorted(sessions.glob("sess_nuclei*"), key=lambda p: p.stat().st_mtime)
if not files:
    raise SystemExit("no matching session files")
latest = files[-1]
print("FILE:", latest.name, "SIZE:", latest.stat().st_size)
print(latest.read_text(errors="replace"))
