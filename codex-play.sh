#!/bin/bash
# Notchy Codex state-update hook.
# Invoked by Codex lifecycle hooks. Reads hook payload JSON from stdin
# when available and writes the current status to ~/.codex/notchy/status.
#
# Usage: codex-play.sh <event-arg>
# Event args:
#   start    -> status=working
#   working  -> status=working
#   complete -> status=idle
#   input    -> status=waiting
#   error    -> status=error

STATE_DIR="$HOME/.codex/notchy"
mkdir -p "$STATE_DIR"

case "$1" in
  start|working) status="working" ;;
  complete)      status="idle" ;;
  input)         status="waiting" ;;
  error)         status="error" ;;
  *) exit 0 ;;
esac

project=""
if [ ! -t 0 ]; then
  payload=$(cat 2>/dev/null || echo "")
  if [ -n "$payload" ]; then
    cwd=$(echo "$payload" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data.get('cwd') or data.get('workspace') or data.get('working_dir') or '')" 2>/dev/null)
    [ -n "$cwd" ] && project=$(basename "$cwd")
  fi
fi

ts=$(date +%s)
printf '%s\t%s\t%s\n' "$status" "$ts" "$project" > "$STATE_DIR/status"

if [ -x "$STATE_DIR/usage.sh" ]; then
  "$STATE_DIR/usage.sh" >/dev/null 2>&1 &
fi

exit 0
