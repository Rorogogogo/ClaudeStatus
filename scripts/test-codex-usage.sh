#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

SESSION_DIR="$TMP_HOME/.codex/sessions/2026/05/16"
mkdir -p "$SESSION_DIR"

cat > "$SESSION_DIR/old.jsonl" <<'JSONL'
{"timestamp":"2026-05-16T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":11.0,"window_minutes":300,"resets_at":1000},"secondary":{"used_percent":22.0,"window_minutes":10080,"resets_at":2000}}}
JSONL

cat > "$SESSION_DIR/new.jsonl" <<'JSONL'
{"timestamp":"2026-05-16T00:00:01.000Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":33.0,"window_minutes":300,"resets_at":3000},"secondary":{"used_percent":44.0,"window_minutes":10080,"resets_at":4000}}}
not json
{"timestamp":"2026-05-16T00:00:02.000Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":55.0,"window_minutes":300,"resets_at":5000},"secondary":{"used_percent":66.0,"window_minutes":10080,"resets_at":6000}}}
{"timestamp":"2026-05-16T00:00:03.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":77.0,"window_minutes":300,"resets_at":7000},"secondary":{"used_percent":88.0,"window_minutes":10080,"resets_at":8000}}}}
JSONL

HOME="$TMP_HOME" "$ROOT/codex-usage.sh"

expected=$'77\t7000\t88\t8000'
actual="$(cat "$TMP_HOME/.codex/notchy/usage")"

if [ "$actual" != "$expected" ]; then
  printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
  exit 1
fi

echo "codex usage test passed"
