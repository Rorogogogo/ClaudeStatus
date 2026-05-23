# Notchy Antigravity Integration Design Specification

This specification outlines the integration of `antigravity-cli` (Gemini CLI) support into the Notchy native macOS notch indicator. Notchy will monitor `antigravity-cli` active state, active project, and idle status via JSON-defined lifecycle hooks, showing it in the collapsed notch pill and expanded panel along with Claude Code and Codex.

---

## 1. High-Level Architecture

Notchy works by watching local state files using macOS kernel `kqueue` notifications (`VNODE_WRITE`). We will establish an identical event-driven state flow for Antigravity:

```
[ Antigravity CLI ] 
       │
       ▼ (fires lifecycle hook)
[ ~/.gemini/config/hooks.json ]
       │
       ▼ (executes command)
[ ~/.gemini/notchy/play.sh <event> ]
       │
       ▼ (writes status tab-separated row)
[ ~/.gemini/notchy/status ]
       │
       ▼ (VNODE_WRITE kernel file watch)
[ Notchy.app ] ──► SwiftUI Renders Pill & Detail Rows
```

---

## 2. Hooks Configuration & Scripting

### 2.1 State Hook Script (`scripts/gemini-play.sh`)
We will create a lightweight shell script installed at `~/.gemini/notchy/play.sh`. The script receives the simplified status name as its first argument and the JSON lifecycle hook payload from standard input.

```bash
#!/bin/bash
# Notchy Antigravity state-update hook.
# Invoked by Antigravity hook events. Reads hook payload JSON from stdin
# when available and writes the current status to ~/.gemini/notchy/status.

STATE_DIR="$HOME/.gemini/notchy"
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
exit 0
```

### 2.2 Hooks Registration (`~/.gemini/config/hooks.json`)
The `postinstall` script will merge these hook definitions into `/Users/roro/.gemini/config/hooks.json` to receive real-time updates:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh start"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh working"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh working"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh working"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh working"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh complete"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh complete"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh input"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/roro/.gemini/notchy/play.sh input"
          }
        ]
      }
    ]
  }
}
```

---

## 3. Swift Models & Application Logic

### 3.1 `AgentKind` (`Sources/Notchy/Models/AgentKind.swift`)
Add a new enum case for the Antigravity agent:
```swift
enum AgentKind {
    case claude
    case codex
    case antigravity
}
```

### 3.2 `AppDelegate` (`Sources/Notchy/AppDelegate.swift`)
Instantiate state models and hooks:
*   Add state and usage models:
    ```swift
    let antigravityStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.gemini/notchy/status")
    let antigravityUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.gemini/notchy/usage")
    ```
*   Listen to state changes in `applicationDidFinishLaunching`:
    ```swift
    antigravityStatus.objectWillChange.sink { [weak self] _ in
        DispatchQueue.main.async { self?.applyVisibility() }
    }
    .store(in: &visibilityCancellables)
    ```
*   Update visibility check:
    ```swift
    let newestEventTs = max(max(claudeStatus.lastEventTs, codexStatus.lastEventTs), antigravityStatus.lastEventTs)
    ```
*   Pass new parameters into `NotchContentView` during `rebuild`.

---

## 4. UI & View Modifications

### 4.1 Custom Sparkle Star Icon (`Sources/Notchy/Views/Icons/AntigravityMark.swift`)
A premium SwiftUI `Canvas`-based four-pointed star matching the Google Gemini/Antigravity design aesthetic with a sleek gradient fill:

```swift
import SwiftUI

struct AntigravityMark: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2
            
            var path = Path()
            path.move(to: CGPoint(x: cx, y: 0))
            path.addQuadCurve(to: CGPoint(x: w, y: cy), control: CGPoint(x: cx + w * 0.16, y: cy - h * 0.16))
            path.addQuadCurve(to: CGPoint(x: cx, y: h), control: CGPoint(x: cx + w * 0.16, y: cy + h * 0.16))
            path.addQuadCurve(to: CGPoint(x: 0, y: cy), control: CGPoint(x: cx - w * 0.16, y: cy + h * 0.16))
            path.addQuadCurve(to: CGPoint(x: cx, y: 0), control: CGPoint(x: cx - w * 0.16, y: cy - h * 0.16))
            
            let gradient = Gradient(colors: [
                Color(red: 0.35, green: 0.65, blue: 1.0),
                Color(red: 0.60, green: 0.40, blue: 1.0)
            ])
            ctx.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: h)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Antigravity")
    }
}
```

### 4.2 Notch Content View (`Sources/Notchy/Views/NotchContentView.swift`)
*   Add `@ObservedObject var antigravityStatus: AgentStatusModel` and `@ObservedObject var antigravityUsage: AgentUsageModel`.
*   Implement `antigravitySnapshot`:
    ```swift
    private var antigravitySnapshot: AgentSnapshot {
        AgentSnapshot(
            kind: .antigravity,
            name: "Antigravity",
            status: effectiveStatus(for: antigravityStatus),
            project: antigravityStatus.project,
            lastEventTs: antigravityStatus.lastEventTs,
            usage: antigravityUsage
        )
    }
    ```
*   Update `activeSnapshot` selection:
    ```swift
    private var activeSnapshot: AgentSnapshot {
        let list = [claudeSnapshot, codexSnapshot, antigravitySnapshot]
        return list.max(by: { $0.lastEventTs < $1.lastEventTs }) ?? claudeSnapshot
    }
    ```
*   In `pillView`, support rendering `AntigravityMark` if active:
    ```swift
    if activeSnapshot.kind == .claude {
        ClaudeCrabIcon(size: 14)
    } else if activeSnapshot.kind == .codex {
        CodexMark(size: 15)
    } else {
        AntigravityMark(size: 14)
    }
    ```
*   In `expandedDetail`, render the third row for `antigravitySnapshot`.
*   Adjust expanded panel height to `collapsedSize.height + 252 + 50 = 342` to comfortably fit the third row.

---

## 5. Build and Installer Customization (`scripts/postinstall`)
*   Include copies/configurations for `~/.gemini/notchy/play.sh`.
*   Merge hook items to `/Users/roro/.gemini/config/hooks.json` cleanly, preserving existing entries.
*   Pre-create `~/.gemini/notchy/status` and `~/.gemini/notchy/usage` (prefilled with mock values `0\t0\t0\t0\t0\t0`) with correct target user permissions.
