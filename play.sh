#!/bin/bash
# ClaudeStatus state-update hook.
# Invoked by Claude Code hook events. Reads hook payload JSON from stdin
# (to extract `cwd`) and writes the current status to ~/.claude/state/status.
#
# Usage: play.sh <event-arg>
# Event args:
#   start    -> status=working (e.g. SessionStart)
#   working  -> status=working (e.g. UserPromptSubmit, PreToolUse, PostToolUse)
#   complete -> status=idle    (e.g. Stop, StopFailure)
#   input    -> status=waiting (e.g. Notification, PermissionRequest)
#   error    -> status=error

STATE_DIR="$HOME/.claude/state"
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
    cwd=$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
    [ -n "$cwd" ] && project=$(basename "$cwd")
  fi
fi

ts=$(date +%s)
printf '%s\t%s\t%s\n' "$status" "$ts" "$project" > "$STATE_DIR/status"
exit 0
