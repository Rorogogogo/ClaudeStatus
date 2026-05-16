#!/bin/bash
# Notchy Codex usage updater.
# Reads recent Codex session JSONL files and writes the latest rate-limit
# percentages to ~/.codex/notchy/usage in Notchy's shared usage format.

set -euo pipefail

CODEX_DIR="$HOME/.codex"
STATE_DIR="$CODEX_DIR/notchy"
SESSIONS_DIR="$CODEX_DIR/sessions"
USAGE_FILE="$STATE_DIR/usage"

mkdir -p "$STATE_DIR"

CODEX_SESSIONS_DIR="$SESSIONS_DIR" CODEX_USAGE_FILE="$USAGE_FILE" python3 - <<'PYEOF'
import json
import os
from pathlib import Path

sessions_dir = Path(os.environ["CODEX_SESSIONS_DIR"])
usage_path = Path(os.environ["CODEX_USAGE_FILE"])

if not sessions_dir.exists():
    raise SystemExit(0)

def format_number(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number.is_integer():
        return str(int(number))
    return f"{number:.1f}".rstrip("0").rstrip(".")

def format_int(value):
    try:
        return str(int(float(value)))
    except (TypeError, ValueError):
        return None

def recent_tail(path, max_bytes=2_000_000):
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - max_bytes))
            data = handle.read()
    except OSError:
        return []
    return data.decode("utf-8", errors="ignore").splitlines()

files = []
for path in sessions_dir.rglob("*.jsonl"):
    try:
        files.append((path.stat().st_mtime, path))
    except OSError:
        pass

latest = None
for _mtime, path in sorted(files, reverse=True)[:30]:
    for line in recent_tail(path):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("payload", {}).get("type") != "token_count":
            continue
        payload = event.get("payload") or {}
        rate_limits = event.get("rate_limits") or payload.get("rate_limits") or {}
        primary = rate_limits.get("primary") or {}
        secondary = rate_limits.get("secondary") or {}
        if not primary or not secondary:
            continue

        primary_pct = format_number(primary.get("used_percent"))
        primary_reset = format_int(primary.get("resets_at"))
        secondary_pct = format_number(secondary.get("used_percent"))
        secondary_reset = format_int(secondary.get("resets_at"))
        if None in (primary_pct, primary_reset, secondary_pct, secondary_reset):
            continue

        timestamp = event.get("timestamp") or ""
        row = (primary_pct, primary_reset, secondary_pct, secondary_reset)
        candidate = (timestamp, row)
        if latest is None or candidate[0] > latest[0]:
            latest = candidate

if latest is None:
    raise SystemExit(0)

usage_path.parent.mkdir(parents=True, exist_ok=True)
tmp_path = usage_path.with_suffix(".tmp")
tmp_path.write_text("\t".join(latest[1]) + "\n")
os.replace(tmp_path, usage_path)
PYEOF
