# Codex Usage Design

## Goal

Show Codex rate-limit usage in Notchy using the same compact usage bars already used for Claude Code.

## Source Data

Codex session JSONL files contain `token_count` events with `rate_limits`. The relevant values are:

- `primary.used_percent`, `primary.resets_at`, `primary.window_minutes`
- `secondary.used_percent`, `secondary.resets_at`, `secondary.window_minutes`

These map cleanly onto Notchy's existing usage file format:

```text
<five_hour_pct>\t<five_hour_reset>\t<weekly_pct>\t<weekly_reset>
```

## Approach

Add `codex-usage.sh`, a small helper installed next to `~/.codex/notchy/play.sh`. The Codex lifecycle hook calls it in the background after each status event. The helper scans the newest Codex session JSONL files, finds the latest `token_count` event with `rate_limits`, and writes `~/.codex/notchy/usage`.

The Swift app already has an `AgentUsageModel` for `~/.codex/notchy/usage`; the UI only needs to render the existing Codex usage model in the Codex row.

## Error Handling

If no usable Codex `rate_limits` event exists, the helper leaves the existing usage file untouched. Invalid JSONL lines are skipped. Missing directories are tolerated.

## Testing

Use a shell test that creates a temporary Codex home with synthetic JSONL sessions and verifies `codex-usage.sh` writes the expected tab-separated usage line.
