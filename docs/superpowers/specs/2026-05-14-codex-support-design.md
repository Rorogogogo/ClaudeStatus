# Codex Support Design

## Goal

Add Codex visibility to Notchy while keeping a single compact notch indicator.
The collapsed notch indicator shows whichever agent, Claude Code or Codex, has
the newest status update. When the user hovers to expand it, Notchy shows both
agents as separate rows.

## Current State

Notchy is currently Claude Code-specific:

- The Swift app watches `~/.claude/state/status` for status and project.
- It watches `~/.claude/state/usage` for 5-hour and weekly usage.
- The installer writes Claude Code hooks into `~/.claude/settings.json`.
- The installer injects or registers a Claude statusline writer for usage data.

Codex provides lifecycle hooks behind `codex_hooks = true`, which can drive the
same status states as Claude Code. Codex usage data is not exposed through the
same statusline mechanism; it may be parsed from Codex session JSONL in a later
iteration if needed.

## User Experience

Collapsed:

- Show one icon and one status dot.
- Choose the displayed agent by newest `lastEventTs`.
- If only one agent has state, show that agent.
- Preserve the current idle auto-hide behavior, based on the newest agent event.

Expanded:

- Show a Claude row with status, project, and usage bars.
- Show a Codex row with status and project.
- Show Codex usage only if a reliable local source is available; otherwise keep
  the Codex row status-focused and avoid fake or estimated numbers.

## Data Model

Use separate state files per provider:

- Claude status: `~/.claude/state/status`
- Claude usage: `~/.claude/state/usage`
- Codex status: `~/.codex/notchy/status`
- Codex usage: `~/.codex/notchy/usage`

Status file format remains:

```text
<status>\t<unix_ts>\t<project_name>
```

Usage file format remains:

```text
<five_hour_pct>\t<five_hour_reset>\t<weekly_pct>\t<weekly_reset>
```

## App Architecture

Replace the single Claude-specific `StatusModel` with reusable per-agent status
models:

- `AgentStatusModel` watches one status path.
- `AgentUsageModel` watches one usage path.
- `AgentSnapshot` contains display name, icon style, status, project, last event,
  and optional usage.
- `NotchContentView` chooses the newest agent snapshot for the collapsed view.
- The expanded detail view renders both snapshots as separate rows.

The first implementation can keep the existing Claude icon and use a simple
Codex text mark or SF Symbol for Codex. A later visual pass can replace it with
a custom Codex icon if desired.

## Installer Behavior

Keep existing Claude setup unchanged.

Add Codex setup:

- Install a Codex hook script under `~/.codex/notchy/play.sh`.
- Ensure `~/.codex/config.toml` exists.
- Set `codex_hooks = true` without deleting unrelated user config.
- Add Codex lifecycle hook commands for:
  - `SessionStart` -> `start`
  - `UserPromptSubmit` -> `working`
  - `PreToolUse` -> `working`
  - `PostToolUse` -> `working`
  - `PostToolUseFailure` -> `working`
  - `Stop` -> `complete`
  - `StopFailure` -> `complete`
  - `Notification` -> `input`
  - `PermissionRequest` -> `input`

The hook script should read Codex hook JSON from stdin, extract the current
working directory if present, and write the shared status format.

## Error Handling

- Missing state files are created with idle/default values.
- Invalid status or usage contents are ignored or coerced to safe defaults.
- If Codex config cannot be parsed safely, the installer should append a small,
  marked Notchy block rather than rewrite the entire config.
- Re-running the installer must be idempotent and must not duplicate hooks.

## Testing

Verification should cover:

- Swift compile through `./build.sh`.
- Hook scripts write the expected status lines for representative JSON payloads.
- Installer text generation remains idempotent for existing Claude setup.
- Codex config changes preserve unrelated config values.

