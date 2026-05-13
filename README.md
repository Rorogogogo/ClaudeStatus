<p align="center">
  <img src="assets/logo.png" width="128" height="128" alt="ClaudeStatus logo" />
</p>

# ClaudeStatus

A tiny, native macOS status indicator for [Claude Code](https://docs.claude.com/en/docs/claude-code) — sits next to your camera in the notch and turns 🟢 / 🟡 / ⚪ as the agent works / waits for you / goes idle.

Built as a lightweight alternative to heavier "dynamic island for Claude" tools. Single Swift binary, no Electron, no Python, no background watchers spinning at 60Hz.

### [⬇️ Download ClaudeStatus.pkg (v1.0.0)](https://github.com/Rorogogogo/ClaudeStatus/releases/latest/download/ClaudeStatus.pkg)

## Why this exists

A passive, glance-and-go indicator. No clickable UI, no chat history, no background animations spinning at 60 Hz — just a tiny dot that tells you whether the agent is working, waiting on you, or idle.

Measured on an M-series MacBook Pro:

- **0.1 % idle CPU** — the only thing running between events is a 250 ms `stat()` poll
- **~29 MB RSS** — single native binary, no framework runtime overhead
- **~180 KB binary** — ~200 lines of Swift, links against the system AppKit / SwiftUI
- **Event-driven** via `kqueue` (`DispatchSource.makeFileSystemObjectSource`), not per-frame redraws

## What it shows

- A small black notch-shaped pill, slightly wider than the physical notch
- 🦀 Coral Claude-style crab icon on the left of the camera
- A colored status dot on the right of the camera:
  - 🟢 **green** — working (you sent a prompt, agent is generating or running a tool)
  - 🟡 **yellow** — waiting on you (permission prompt or other input needed)
  - ⚪ **gray** — idle (last turn finished cleanly)
- Hides itself completely after 10 minutes of no activity, reappears the instant any Claude Code hook fires.

## Requirements

- macOS 14 (Sonoma) or later
- A MacBook with a notch (M-series 14"/16" Pro, M3 Air, etc.)
- Claude Code installed
- For building from source: Xcode Command Line Tools (`xcode-select --install`)

## Install (from the .pkg)

1. Download `ClaudeStatus.pkg` from the [Releases](https://github.com/Rorogogogo/ClaudeStatus/releases) page.
2. Right-click → **Open** (since the package isn't signed with a paid Apple Developer ID, double-clicking will be blocked by Gatekeeper).
3. Walk through the macOS Installer.
4. **Restart any running Claude Code session.** Hooks only load at session start.

The installer's postinstall script will:

- Copy the app to `/Applications/ClaudeStatus.app`
- Install `play.sh` to `~/.claude/sounds/peon-ping/play.sh`
- Merge hook entries into `~/.claude/settings.json` (existing hooks are preserved)
- Write a LaunchAgent at `~/Library/LaunchAgents/com.claudestatus.app.plist`
- Start the app immediately and on every login

Re-running the installer is safe — it replaces (doesn't duplicate) the ClaudeStatus hook entries.

## Build from source

```bash
git clone https://github.com/Rorogogogo/ClaudeStatus.git
cd ClaudeStatus
./build.sh
```

Outputs:
- `build/ClaudeStatus.app` — the standalone app
- `build/ClaudeStatus.pkg` — the installer

## How it works

Three pieces:

1. **`play.sh`** — invoked by Claude Code hook events. Reads the hook's JSON payload from stdin, extracts the working directory, writes `<status>\t<unix_ts>\t<project_name>\n` to `~/.claude/state/status`. ~20 ms per invocation.

2. **`~/.claude/state/status`** — single text file that holds the current state. Updated by `play.sh` on every hook event.

3. **`ClaudeStatus.app`** — a long-running native macOS app:
   - Floating `NSPanel` over the physical notch, level above the menu bar, ignores mouse events
   - Notch-shaped pill drawn with a custom `Shape` (top corner radius 6 inward, bottom 14 outward — same curves as the iPhone Dynamic Island)
   - Watches `~/.claude/state/status` with a `DispatchSource.makeFileSystemObjectSource` (`kqueue` under the hood). Re-reads only when the kernel fires a `VNODE_WRITE`. A 250 ms `stat()` poll is the belt-and-suspenders backup.
   - Auto-expires `waiting` to `idle` after 3 s, because Claude Code doesn't emit a hook when a user denies a permission prompt (see [Caveats](#caveats)).

## Hooks installed

| Claude Code event | Sets status to |
|---|---|
| `SessionStart` | working |
| `UserPromptSubmit` | working |
| `PreToolUse` | working |
| `PostToolUse` | working |
| `PostToolUseFailure` | working |
| `Stop` | idle |
| `StopFailure` | idle |
| `Notification` | waiting |
| `PermissionRequest` | waiting |

## Caveats

- **No hook fires when the user denies a permission prompt** ([per the docs](https://docs.claude.com/en/docs/claude-code/hooks)). ClaudeStatus handles this by auto-expiring `waiting` → `idle` after 3 seconds with no further events.
- **Hooks load at session start.** After installing (or reconfiguring), restart any running Claude Code session.
- **First-launch Gatekeeper warning.** The `.pkg` isn't notarized — right-click → Open the first time, or notarize it yourself if distributing widely.
- **Notch-only.** Older / non-notch displays still get a pill at the top center, but it looks less like a natural notch extension.

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/com.claudestatus.app" 2>/dev/null || \
  launchctl unload ~/Library/LaunchAgents/com.claudestatus.app.plist
rm -rf /Applications/ClaudeStatus.app
rm -f ~/Library/LaunchAgents/com.claudestatus.app.plist
rm -rf ~/.claude/sounds/peon-ping
```

Then remove ClaudeStatus's hook entries from `~/.claude/settings.json` — they all reference `~/.claude/sounds/peon-ping/play.sh`.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Notch shape geometry and the crab icon concept inspired by [farouqaldori/vibe-notch](https://github.com/farouqaldori/vibe-notch) (Apache 2.0).
