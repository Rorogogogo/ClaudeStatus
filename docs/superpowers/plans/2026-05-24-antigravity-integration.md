# Antigravity CLI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the `antigravity-cli` (Gemini CLI) agent status and tracking natively into Notchy, displaying it side-by-side with Claude Code and Codex.

**Architecture:** We use Antigravity CLI's JSON lifecycle hooks configured in `~/.gemini/config/hooks.json` to execute a shell script that writes to `~/.gemini/notchy/status`. Notchy.app monitors this state file via `kqueue` kernel file-watches, updating its models and rendering a beautiful custom-drawn neon-gradient four-pointed Gemini star row in the SwiftUI panel.

**Tech Stack:** macOS Swift, AppKit, SwiftUI, Shell scripting, Python 3, JSON

---

### Task 1: Create the Antigravity Hook Script

**Files:**
- Create: `scripts/gemini-play.sh`
- Test: Manual execution of `scripts/gemini-play.sh` with mock JSON payload

- [ ] **Step 1: Write the hook script**
  Create the state updater script to handle incoming hook events and parse the JSON payload from standard input.

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

- [ ] **Step 2: Verify manual script execution**
  Run the script with a simulated JSON input and verify it writes the status line accurately.

Run:
```bash
chmod +x scripts/gemini-play.sh
echo '{"cwd": "/Users/roro/test-project"}' | ./scripts/gemini-play.sh working
cat ~/.gemini/notchy/status
```
Expected output:
`working` followed by the current Unix timestamp and `test-project` separated by tabs.

- [ ] **Step 3: Commit**
```bash
git add scripts/gemini-play.sh
git commit -m "feat: add gemini-play.sh state-update hook script"
```

---

### Task 2: Swift Models Configuration

**Files:**
- Modify: `Sources/Notchy/Models/AgentKind.swift`
- Modify: `Sources/Notchy/AppDelegate.swift`

- [ ] **Step 1: Update AgentKind enum**
  Modify `Sources/Notchy/Models/AgentKind.swift` to add `.antigravity`:

```swift
enum AgentKind {
    case claude
    case codex
    case antigravity
}
```

- [ ] **Step 2: Instantiate models in AppDelegate**
  Add state and usage observers to `Sources/Notchy/AppDelegate.swift`:

Modify `Sources/Notchy/AppDelegate.swift` around line 10 to include `antigravityStatus` and `antigravityUsage`:
```swift
    let claudeStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.claude/state/status")
    let claudeUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.claude/state/usage")
    let codexStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.codex/notchy/status")
    let codexUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.codex/notchy/usage")
    let antigravityStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.gemini/notchy/status")
    let antigravityUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.gemini/notchy/usage")
```

- [ ] **Step 3: Subscribe to state changes in applicationDidFinishLaunching**
  Modify `Sources/Notchy/AppDelegate.swift` inside `applicationDidFinishLaunching` around line 50:

```swift
        codexStatus.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyVisibility() }
        }
        .store(in: &visibilityCancellables)

        antigravityStatus.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyVisibility() }
        }
        .store(in: &visibilityCancellables)
```

- [ ] **Step 4: Update visibility max-event calculations**
  Modify `Sources/Notchy/AppDelegate.swift` in `applyVisibility()` around line 90:

```swift
    func applyVisibility() {
        guard let panel else { return }
        let now = Int(Date().timeIntervalSince1970)
        let newestEventTs = max(max(claudeStatus.lastEventTs, codexStatus.lastEventTs), antigravityStatus.lastEventTs)
        let age = now - newestEventTs
        let shouldShow = newestEventTs > 0 && TimeInterval(age) < idleHideAfterSeconds
```

- [ ] **Step 5: Pass the new models to NotchContentView in rebuild()**
  Modify `Sources/Notchy/AppDelegate.swift` in `rebuild()` around line 130:

```swift
        let p = NotchPanel(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        setHovering(false)
        let host = NSHostingView(rootView: NotchContentView(
            claudeStatus: claudeStatus,
            claudeUsage: claudeUsage,
            codexStatus: codexStatus,
            codexUsage: codexUsage,
            antigravityStatus: antigravityStatus,
            antigravityUsage: antigravityUsage,
            collapsedSize: collapsedSize,
            expandedSize: expandedSize,
            hoverState: hoverState
        ))
```

- [ ] **Step 6: Update panel size constraints to accommodate the third row**
  Modify `Sources/Notchy/AppDelegate.swift` in `rebuild()` around line 115:

```swift
        // Expanded pill: wider for the weekly bar + labels, taller for the detail blocks.
        let expandedSize = CGSize(
            width:  max(390, collapsedSize.width + 90),
            height: collapsedSize.height + 252 + 52 // Add 52pt vertical space for third row
        )
```

- [ ] **Step 7: Verify project builds**
  Compile the Swift codebase to verify no syntax errors so far.

Run:
```bash
./build.sh
```
Expected: The project builds successfully (warnings about unused variables in NotchContentView instantiation are acceptable).

- [ ] **Step 8: Commit**
```bash
git add Sources/Notchy/Models/AgentKind.swift Sources/Notchy/AppDelegate.swift
git commit -m "feat: add Antigravity status models and panel constraints in AppDelegate"
```

---

### Task 3: UI Assets and Views Integration

**Files:**
- Create: `Sources/Notchy/Views/Icons/AntigravityMark.swift`
- Modify: `Sources/Notchy/Views/NotchContentView.swift`

- [ ] **Step 1: Create custom-drawn Sparkle Star Icon**
  Write the SwiftUI `Canvas` view for `AntigravityMark.swift`:

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

- [ ] **Step 2: Add observed models in NotchContentView**
  Modify `Sources/Notchy/Views/NotchContentView.swift` around line 15:

```swift
struct NotchContentView: View {
    @ObservedObject var claudeStatus: AgentStatusModel
    @ObservedObject var claudeUsage: AgentUsageModel
    @ObservedObject var codexStatus: AgentStatusModel
    @ObservedObject var codexUsage: AgentUsageModel
    @ObservedObject var antigravityStatus: AgentStatusModel
    @ObservedObject var antigravityUsage: AgentUsageModel
    @StateObject private var repoStats = GitHubRepoStatsModel()
```

- [ ] **Step 3: Add snapshot and active-agent resolving logic**
  Modify `Sources/Notchy/Views/NotchContentView.swift` around line 35 to add `antigravitySnapshot` and include it in `activeSnapshot`:

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

    private var activeSnapshot: AgentSnapshot {
        let list = [claudeSnapshot, codexSnapshot, antigravitySnapshot]
        return list.max(by: { $0.lastEventTs < $1.lastEventTs }) ?? claudeSnapshot
    }
```

- [ ] **Step 4: Update collapsed icon rendering**
  Modify `Sources/Notchy/Views/NotchContentView.swift` inside `pillView` around line 115 to render the star icon:

```swift
                HStack(spacing: 0) {
                    Spacer().frame(width: hovering ? 22 : 14)
                    if activeSnapshot.kind == .claude {
                        ClaudeCrabIcon(size: 14)
                    } else if activeSnapshot.kind == .codex {
                        CodexMark(size: 15)
                    } else {
                        AntigravityMark(size: 14)
                    }
                    Spacer(minLength: 0)
```

- [ ] **Step 5: Render Antigravity in expanded detail panel**
  Modify `Sources/Notchy/Views/NotchContentView.swift` inside `expandedDetail` around line 140:

```swift
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            agentRow(claudeSnapshot, showUsage: true)
            Divider().background(Color.white.opacity(0.12))
            agentRow(codexSnapshot, showUsage: true)
            Divider().background(Color.white.opacity(0.12))
            agentRow(antigravitySnapshot, showUsage: false)
            footerControls
                .padding(.top, 4)
        }
    }
```

- [ ] **Step 6: Update agent row icon rendering**
  Modify `Sources/Notchy/Views/NotchContentView.swift` inside `agentRow` around line 255:

```swift
    private func agentRow(_ snapshot: AgentSnapshot, showUsage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if snapshot.kind == .claude {
                    ClaudeCrabIcon(size: 12)
                } else if snapshot.kind == .codex {
                    CodexMark(size: 13)
                } else {
                    AntigravityMark(size: 12)
                }
                Text(snapshot.name)
```

- [ ] **Step 7: Compile and verify project builds**
  Ensure there are no build errors with the SwiftUI and icon integration.

Run:
```bash
./build.sh
```
Expected: The project builds successfully with no compilation errors.

- [ ] **Step 8: Commit**
```bash
git add Sources/Notchy/Views/Icons/AntigravityMark.swift Sources/Notchy/Views/NotchContentView.swift
git commit -m "feat: draw Google Gemini-like sparkle star icon and display Antigravity row"
```

---

### Task 4: Installer Integration and Hooks Orchestration

**Files:**
- Modify: `scripts/postinstall`

- [ ] **Step 1: Add new target variables and copy commands**
  Modify `scripts/postinstall` around line 35 to add variables for the new hook script and state paths:

```bash
CODEX_USAGE_SH="$CODEX_NOTCHY_DIR/usage.sh"
GEMINI_DIR="$TARGET_HOME/.gemini"
GEMINI_NOTCHY_DIR="$GEMINI_DIR/notchy"
GEMINI_CONFIG_FILE="$GEMINI_DIR/config/hooks.json"
GEMINI_PLAY_SH="$GEMINI_NOTCHY_DIR/play.sh"
LAUNCH_AGENT_DIR="$TARGET_HOME/Library/LaunchAgents"
```

Modify around line 46 to create directories and copy the script:
```bash
echo "postinstall: target user=$TARGET_USER home=$TARGET_HOME"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$NOTCHY_DIR" "$STATE_DIR" "$LAUNCH_AGENT_DIR" "$CLAUDE_DIR" "$CODEX_NOTCHY_DIR" "$GEMINI_NOTCHY_DIR"
cp "$SCRIPT_DIR/play.sh" "$PLAY_SH"
chmod +x "$PLAY_SH"
cp "$SCRIPT_DIR/codex-play.sh" "$CODEX_PLAY_SH"
chmod +x "$CODEX_PLAY_SH"
cp "$SCRIPT_DIR/codex-usage.sh" "$CODEX_USAGE_SH"
chmod +x "$CODEX_USAGE_SH"
cp "$SCRIPT_DIR/gemini-play.sh" "$GEMINI_PLAY_SH"
chmod +x "$GEMINI_PLAY_SH"
```

- [ ] **Step 2: Merge hook entries into ~/.gemini/config/hooks.json**
  Modify `scripts/postinstall` around line 305 to add a python segment that merges hooks for `antigravity-cli` (exactly mimicking the Codex merge):

```bash
# --- Merge Antigravity hooks (status colors) ---
GEMINI_CONFIG_FOR_PY="$GEMINI_CONFIG_FILE" \
GEMINI_PLAY_FOR_PY="$GEMINI_PLAY_SH" \
python3 - <<'PYEOF'
import json, os
from pathlib import Path

config_path = Path(os.environ["GEMINI_CONFIG_FOR_PY"])
play_sh = os.environ["GEMINI_PLAY_FOR_PY"]

config_path.parent.mkdir(parents=True, exist_ok=True)

events = {
    "SessionStart": ("start", "Notchy: mark Antigravity active"),
    "UserPromptSubmit": ("working", "Notchy: mark Antigravity working"),
    "PreToolUse": ("working", "Notchy: mark Antigravity working before tool use"),
    "PostToolUse": ("working", "Notchy: keep Antigravity marked working after tool use"),
    "PostToolUseFailure": ("working", "Notchy: keep Antigravity marked working after tool failure"),
    "Stop": ("complete", "Notchy: mark Antigravity idle"),
    "StopFailure": ("complete", "Notchy: mark Antigravity idle after failed turn"),
    "Notification": ("input", "Notchy: mark Antigravity waiting for input"),
    "PermissionRequest": ("input", "Notchy: mark Antigravity waiting for permission"),
}

try:
    data = json.loads(config_path.read_text()) if config_path.exists() else {}
except json.JSONDecodeError:
    data = {}

hooks = data.setdefault("hooks", {})

def is_ours(command):
    return "/.gemini/notchy/play.sh" in command

for event, (arg, status_message) in events.items():
    desired = f"{play_sh} {arg}"
    filtered = []
    for group in hooks.get(event, []):
        kept = [h for h in group.get("hooks", []) if not is_ours(h.get("command", ""))]
        if kept:
            new_group = {k: v for k, v in group.items() if k != "hooks"}
            new_group["hooks"] = kept
            filtered.append(new_group)
    entry = {"hooks": [{"type": "command", "command": desired, "statusMessage": status_message}]}
    if event in ("PermissionRequest", "PreToolUse", "PostToolUse", "PostToolUseFailure"):
        entry["matcher"] = "*"
    filtered.append(entry)
    hooks[event] = filtered

config_path.write_text(json.dumps(data, indent=2) + "\n")
PYEOF
```

- [ ] **Step 3: Pre-create state files with correct permissions**
  Modify `scripts/postinstall` around line 324 to set permissions on the new directories and state files:

```bash
chown -R "$TARGET_USER" "$CLAUDE_DIR" "$APP_LAUNCH_AGENT"
[ -d "$CODEX_DIR" ] && chown "$TARGET_USER" "$CODEX_DIR"
[ -f "$CODEX_CONFIG_FILE" ] && chown "$TARGET_USER" "$CODEX_CONFIG_FILE"
[ -f "$CODEX_HOOKS_FILE" ] && chown "$TARGET_USER" "$CODEX_HOOKS_FILE"
[ -d "$CODEX_NOTCHY_DIR" ] && chown -R "$TARGET_USER" "$CODEX_NOTCHY_DIR"

# Pre-create state files & set correct ownership for Antigravity state directory
mkdir -p "$GEMINI_DIR/notchy"
if [ ! -f "$GEMINI_DIR/notchy/status" ]; then
  printf "idle\t0\t\n" > "$GEMINI_DIR/notchy/status"
fi
if [ ! -f "$GEMINI_DIR/notchy/usage" ]; then
  printf "0\t0\t0\t0\t0\t0\n" > "$GEMINI_DIR/notchy/usage"
fi
chown -R "$TARGET_USER" "$GEMINI_DIR"
```

- [ ] **Step 4: Commit**
```bash
git add scripts/postinstall
git commit -m "feat: register gemini hooks config and copy scripts in postinstall"
```

---

### Task 5: End-to-End Verification

- [ ] **Step 1: Build the installer package**
  Build a fresh version of the `.pkg` installer from the compiled app and scripts.

Run:
```bash
./build.sh
```
Expected: Compiles with no errors and generates `build/Notchy.pkg`.

- [ ] **Step 2: Deploy / run postinstall manually as root**
  Simulate installation by running the `postinstall` script directly.

Run:
```bash
sudo ./scripts/postinstall
```
Expected: Completes with `postinstall: done.` and successfully registers the launch agent and hooks.

- [ ] **Step 3: Verify ~/.gemini/config/hooks.json is populated**
  Verify the hooks are registered in the active config.

Run:
```bash
cat ~/.gemini/config/hooks.json
```
Expected: Output matches Task 1's hook JSON schema.

- [ ] **Step 4: Verify the app runs and watches Antigravity status**
  Trigger a simulated Antigravity hook event and watch the Notchy UI status.

Run:
```bash
echo '{"cwd": "/Users/roro/Downloads/work/Personal Project/Notchy"}' | ~/.gemini/notchy/play.sh working
```
Expected: Notchy pill displays the custom neon sparkle icon and a green working status dot.

Run:
```bash
echo '{"cwd": "/Users/roro/Downloads/work/Personal Project/Notchy"}' | ~/.gemini/notchy/play.sh complete
```
Expected: Notchy pill transitions to gray idle dot.
