# Antigravity Integration — Lean Redesign

**Date:** 2026-05-24
**Branch:** `feat/antigravity-v2`
**Supersedes:** the abandoned `feat/antigravity-integration` design (same date)

## Why this is a rewrite

The first attempt was rolled back. The reason it "lagged" was **not** the Antigravity
feature — it was pre-existing perf debt in main's base code (synchronous file I/O on the
main thread, a 1.0 s tick timer forcing re-renders, a `Canvas`-drawn animated icon). Those
fixes now live on this branch as standalone `perf:` commits. The Antigravity work itself
should add **exactly one more agent** and nothing else.

This redesign exists to keep that promise. Its guiding rule:

> **Antigravity is just a third `AgentKind`.** Anything that isn't "another instance of the
> Claude/Codex pattern" is out of scope.

## Goal

Show Antigravity (Gemini CLI / `antigravity-cli`) alongside Claude and Codex:
- its icon + status dot in the collapsed notch pill when it's the most-recent active agent;
- a status row in the expanded panel (agent name · project · status).

## Non-goals (deliberately cut from v1)

- **No usage/quota bars for Antigravity.** Antigravity does not expose a 5h/weekly quota
  the way Claude/Codex do. We will not fabricate one. Status-only row. (Revisit only if the
  CLI later exposes real numbers.)
- **No animated icon.** The old `AntigravityMark` used an animated `Canvas` — the single
  biggest avoidable cost. The icon is a **static SwiftUI `Shape`**, rendered once and cached.
- **No new timers, no new polling loop, no new threads.** Reuse the existing kqueue file
  watch + background poll in `AgentStatusModel`. Adding an agent must add zero new wakeups.
- **No bespoke models or views.** Reuse `AgentStatusModel` and `agentRow(...)` verbatim.

## Architecture (identical to Codex/Claude)

```
[ antigravity-cli ]
   │  fires lifecycle hook
   ▼
~/.gemini/config/hooks.json   ← merged in by postinstall
   │  runs command
   ▼
~/.gemini/notchy/play.sh <event>   ← writes one tab-separated line
   │
   ▼
~/.gemini/notchy/status   "working\t<unix-ts>\t<project>"
   │  kqueue VNODE write event (already handled by AgentStatusModel)
   ▼
Notchy.app → SwiftUI re-render of pill + rows
```

No new mechanism. `AgentStatusModel(path:)` already does the watch, the debounced
background `attributesOfItem` poll, and the wait-state expiry. We just point a third
instance at the gemini path.

## File-by-file changes

All changes are additive and mirror an existing `.codex` line.

### 1. `Sources/Notchy/Models/AgentKind.swift`
```swift
enum AgentKind {
    case claude
    case codex
    case antigravity   // + add
}
```

### 2. `Sources/Notchy/Views/Icons/AntigravityMark.swift` (new)
A **static** four-point Gemini sparkle as a `Shape` (no `Canvas`, no animation, no timers).
Follows `CodexMark`/`ClaudeCrabIcon` API: `var size: CGFloat`, fixed color, `.frame(size)`.

```swift
import SwiftUI

struct AntigravitySparkle: Shape {
    func path(in rect: CGRect) -> Path {
        // 4-point star: tips at N/E/S/W, waist pinched to center.
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * 0.32                       // waist half-width
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))            // top tip
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y),    // right tip
                       control: CGPoint(x: c.x + w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r),    // bottom tip
                       control: CGPoint(x: c.x + w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y),    // left tip
                       control: CGPoint(x: c.x - w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r),    // back to top
                       control: CGPoint(x: c.x - w, y: c.y - w))
        p.closeSubpath()
        return p
    }
}

struct AntigravityMark: View {
    var size: CGFloat = 14
    var body: some View {
        AntigravitySparkle()
            .fill(Color(red: 0.36, green: 0.56, blue: 0.96)) // Gemini blue
            .frame(width: size, height: size)
    }
}
```

### 3. `Sources/Notchy/AppDelegate.swift`
Add two model instances next to the codex ones and pass them into the view:
```swift
let antigravityStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.gemini/notchy/status")
// (no antigravityUsage — status-only)
```
- In `applyVisibility()` extend `newestEventTs` to include `antigravityStatus.lastEventTs`.
- Subscribe `antigravityStatus.objectWillChange` for visibility (mirror codex `sink`).
- Pass `antigravityStatus` into `NotchContentView(...)`.
- Bump `expandedSize.height` by **~44** (one status-only row + divider). Currently
  `collapsedSize.height + 252` → `+ 296`.

### 4. `Sources/Notchy/Views/NotchContentView.swift`
- Add `@ObservedObject var antigravityStatus: AgentStatusModel`.
- Add `antigravitySnapshot` (kind `.antigravity`, name `"Antigravity"`, `usage: nil`).
- Extend `activeSnapshot` to pick the max-`lastEventTs` of **three** snapshots.
- In `pillView` icon switch and `agentRow(...)` icon switch, add the `.antigravity → AntigravityMark` case.
- In `expandedDetail`, add a third `agentRow(antigravitySnapshot, showUsage: false)` with a
  `Divider()` above it.
- `agentRow` already supports `showUsage: false` → renders header only. No change needed there.

### 5. `scripts/gemini-play.sh` (new) + `scripts/postinstall` + `build.sh`
- `gemini-play.sh`: byte-for-byte the shape of `codex-play.sh` — map
  `start/working → working`, `complete → idle`, `input → waiting`, `error → error`; parse
  `cwd`/`workspace` from stdin JSON for the project basename; write
  `status\t<ts>\t<project>` to `~/.gemini/notchy/status`. Mirror `codex-play.sh`'s exact
  JSON parse (`python3 ... data.get('cwd') or data.get('workspace') ...` with `2>/dev/null`
  fallback to an empty project), so behavior is identical to the Codex hook. Drop the
  trailing `usage.sh` invocation — Antigravity has no usage file. (Note: like Codex, this
  uses `python3`; if it's absent the project name is simply blank and status still works.)
- `postinstall`: install the script to `~/.gemini/notchy/play.sh` and merge the hook block
  into `~/.gemini/config/hooks.json`, mirroring the codex/claude registration already there.
  Must be idempotent and must not clobber existing user hooks.
- `build.sh`: copy `gemini-play.sh` into the pkg `scripts/` dir (one line, next to
  `codex-play.sh`).

## Performance guardrails (the whole point)

| Rule | Enforced by |
|------|-------------|
| No new repeating timers | reuse `AgentStatusModel`'s existing watch/poll |
| No main-thread disk I/O | `AgentStatusModel` already polls on a background queue |
| Static icon, GPU-composited | `AntigravityMark` is a `Shape`, never `Canvas` |
| No forced periodic re-render | no `tickTimer` for status-only (no wait-bar animation) |
| Collapsed pill stays click-through | unchanged — no new hit-testing surfaces |

If a change can't be expressed as "another `.codex` line," stop and reconsider.

## Implementation checklist

1. [ ] `AgentKind` += `.antigravity`
2. [ ] `AntigravityMark.swift` (static `Shape`)
3. [ ] `AppDelegate`: model instance, visibility wiring, view param, height +44
4. [ ] `NotchContentView`: snapshot, 3-way `activeSnapshot`, icon cases, third row
5. [ ] `gemini-play.sh` (no python3), `postinstall` merge, `build.sh` copy
6. [ ] `build.sh` → install → verify

## Test plan

- **Build:** `./build.sh` compiles clean (warnings OK).
- **Static-state:** `printf 'working\t%s\tmyproj\n' "$(date +%s)" > ~/.gemini/notchy/status`
  → notch appears, sparkle icon + green dot; expand shows the Antigravity row with project
  `myproj` and status `working`.
- **Recency:** write to gemini status last → collapsed pill shows the sparkle (it's newest).
- **Idle/expiry:** `input` → dot goes amber, returns to idle after ~3 s with no new event.
- **Perf:** re-run the `sample` check — main thread must show **no** `attributesOfItem`
  /`contentsOfFile` frames; idle CPU stays ~0.x%; hover-expand is smooth at 120 Hz.
- **Non-regression:** Claude and Codex rows unchanged; no second notch; quitting works.

## Rollout

Land as small commits on `feat/antigravity-v2`:
`feat: AgentKind .antigravity` → `feat: AntigravityMark sparkle` →
`feat: wire antigravity status + row` → `feat: gemini hook script + postinstall`.
Keep each reviewable; none should touch timer/threading code.
```
