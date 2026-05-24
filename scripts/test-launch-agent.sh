#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
plist="$(sed -n '/^cat > "\$APP_LAUNCH_AGENT" <<EOF$/,/^EOF$/p' "$ROOT/scripts/postinstall" | sed '1d;$d')"

if ! printf '%s\n' "$plist" | grep -q '<key>RunAtLoad</key><true/>'; then
  echo "expected LaunchAgent to start Notchy at login with RunAtLoad" >&2
  exit 1
fi

if printf '%s\n' "$plist" | grep -q '<key>KeepAlive</key>'; then
  echo "expected LaunchAgent not to force-relaunch Notchy after the user quits" >&2
  exit 1
fi

echo "launch agent test passed"
