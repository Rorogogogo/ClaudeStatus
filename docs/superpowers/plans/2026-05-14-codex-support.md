# Codex Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Codex status support so the collapsed Notchy indicator shows the newest agent and the expanded view shows Claude and Codex separately.

**Architecture:** Generalize the existing Claude-only Swift state watchers into reusable agent models, render a two-agent expanded view, and add installer wiring for Codex hooks. Claude usage remains unchanged; Codex initially shows status/project only because Codex usage is not exposed through the same statusline feed.

**Tech Stack:** Swift/AppKit/SwiftUI, Bash, Python 3 for installer JSON/TOML-safe text updates, macOS LaunchAgent packaging through `build.sh`.

---

## File Structure

- Modify `main.swift`: replace Claude-specific status/usage models with reusable `AgentStatusModel` and `AgentUsageModel`, add `AgentSnapshot`, choose newest snapshot for collapsed rendering, and render Claude/Codex rows in expanded state.
- Modify `play.sh`: make comments provider-neutral or leave behavior-compatible for Claude.
- Create `codex-play.sh`: hook script installed under `~/.codex/notchy/play.sh`; maps Codex hook arguments to the shared status format.
- Modify `build.sh`: stage both `play.sh` and `codex-play.sh` into the package scripts directory.
- Modify `scripts/postinstall`: copy the Codex hook script, create/update `~/.codex/config.toml`, write `~/.codex/hooks.json`, and preserve the existing Claude setup.
- Modify `README.md`: document Claude + Codex behavior and caveats.

## Task 1: Add Codex Hook Script

**Files:**
- Create: `codex-play.sh`
- Modify: `build.sh`

- [ ] **Step 1: Create `codex-play.sh`**

Use the same state format as Claude but write under `~/.codex/notchy/status`:

```bash
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
exit 0
```

- [ ] **Step 2: Make `build.sh` stage the Codex script**

In the stage section, add:

```bash
cp "$ROOT/codex-play.sh" "$BUILD/scripts/codex-play.sh"
chmod +x "$BUILD/scripts/postinstall" "$BUILD/scripts/play.sh" "$BUILD/scripts/codex-play.sh"
```

- [ ] **Step 3: Verify the hook script manually**

Run:

```bash
tmp_home="$(mktemp -d)"
HOME="$tmp_home" ./codex-play.sh working <<'JSON'
{"cwd":"/tmp/example-project"}
JSON
cat "$tmp_home/.codex/notchy/status"
```

Expected output shape:

```text
working	<unix_ts>	example-project
```

## Task 2: Add Codex Installer Wiring

**Files:**
- Modify: `scripts/postinstall`
- Modify: `build.sh`

- [ ] **Step 1: Add Codex paths near the existing Claude paths**

Add:

```bash
CODEX_DIR="$TARGET_HOME/.codex"
CODEX_NOTCHY_DIR="$CODEX_DIR/notchy"
CODEX_CONFIG_FILE="$CODEX_DIR/config.toml"
CODEX_HOOKS_FILE="$CODEX_DIR/hooks.json"
CODEX_PLAY_SH="$CODEX_NOTCHY_DIR/play.sh"
```

- [ ] **Step 2: Copy Codex hook script in `postinstall`**

After the Claude `play.sh` copy, add:

```bash
mkdir -p "$CODEX_NOTCHY_DIR"
cp "$SCRIPT_DIR/codex-play.sh" "$CODEX_PLAY_SH"
chmod +x "$CODEX_PLAY_SH"
```

- [ ] **Step 3: Add a Python config writer for Codex**

After the Claude settings/statusline Python block, add a second Python block:

```bash
CODEX_CONFIG_FOR_PY="$CODEX_CONFIG_FILE" \
CODEX_HOOKS_FOR_PY="$CODEX_HOOKS_FILE" \
CODEX_PLAY_FOR_PY="$CODEX_PLAY_SH" \
python3 - <<'PYEOF'
import json, os, re
from pathlib import Path

config_path = Path(os.environ["CODEX_CONFIG_FOR_PY"])
hooks_path = Path(os.environ["CODEX_HOOKS_FOR_PY"])
play_sh = os.environ["CODEX_PLAY_FOR_PY"]

config_path.parent.mkdir(parents=True, exist_ok=True)
content = config_path.read_text() if config_path.exists() else ""

if "[features]" not in content:
    content = content.rstrip() + "\n\n[features]\ncodex_hooks = true\n"
elif re.search(r"(?m)^\s*codex_hooks\s*=", content):
    content = re.sub(r"(?m)^(\s*)codex_hooks\s*=.*$", r"\1codex_hooks = true", content)
else:
    content = re.sub(r"(?m)^(\[features\]\s*)$", r"\1\ncodex_hooks = true", content, count=1)

config_path.write_text(content)

events = {
    "SessionStart": "start",
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
    "PostToolUse": "working",
    "PostToolUseFailure": "working",
    "Stop": "complete",
    "StopFailure": "complete",
    "Notification": "input",
    "PermissionRequest": "input",
}

try:
    data = json.loads(hooks_path.read_text()) if hooks_path.exists() else {}
except json.JSONDecodeError:
    data = {}

hooks = data.setdefault("hooks", {})

def is_ours(command):
    return "/.codex/notchy/play.sh" in command

for event, arg in events.items():
    desired = f"{play_sh} {arg}"
    filtered = []
    for group in hooks.get(event, []):
        kept = [h for h in group.get("hooks", []) if not is_ours(h.get("command", ""))]
        if kept:
            new_group = {k: v for k, v in group.items() if k != "hooks"}
            new_group["hooks"] = kept
            filtered.append(new_group)
    entry = {"hooks": [{"type": "command", "command": desired}]}
    if event in ("PermissionRequest", "PreToolUse", "PostToolUse", "PostToolUseFailure"):
        entry["matcher"] = "*"
    filtered.append(entry)
    hooks[event] = filtered

hooks_path.write_text(json.dumps(data, indent=2) + "\n")
PYEOF
```

- [ ] **Step 4: Extend ownership fix**

Change:

```bash
chown -R "$TARGET_USER" "$CLAUDE_DIR" "$APP_LAUNCH_AGENT"
```

To:

```bash
chown -R "$TARGET_USER" "$CLAUDE_DIR" "$CODEX_DIR" "$APP_LAUNCH_AGENT"
```

- [ ] **Step 5: Verify config writer idempotency in a temp home**

Run the `postinstall` script only through code inspection for now because it is intended for macOS Installer/root context. Verify the embedded Python block by extracting it manually if needed, then run:

```bash
./build.sh
```

Expected: package build succeeds and `build/scripts/codex-play.sh` exists.

## Task 3: Generalize Swift State Models

**Files:**
- Modify: `main.swift`

- [ ] **Step 1: Replace `StatusModel` with `AgentStatusModel`**

Use this shape:

```swift
@MainActor
final class AgentStatusModel: ObservableObject {
    @Published var status: String = "idle"
    @Published var project: String = ""
    @Published var lastEventTs: Int = 0

    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lastMtime: Date?
    private let statePath: String

    init(path: String) {
        statePath = path
        ensureFileExists()
        reload()
        watchFile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollIfChanged()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }
}
```

Keep the existing `ensureFileExists`, `pollIfChanged`, `reload`, and `watchFile` method bodies, using `statePath`.

- [ ] **Step 2: Replace `UsageModel` with `AgentUsageModel`**

Use this initializer shape:

```swift
@MainActor
final class AgentUsageModel: ObservableObject {
    @Published var blockPct: Double = 0
    @Published var weeklyPct: Double = 0
    @Published var blockResetUnix: Int = 0
    @Published var weeklyResetUnix: Int = 0

    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var lastMtime: Date?
    private let path: String

    init(path: String, createIfMissing: Bool = true) {
        self.path = path
        if createIfMissing { ensureFileExists() }
        reload()
        watchFile()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollIfChanged()
        }
    }
}
```

Keep the existing parsing behavior. Codex usage can point at `~/.codex/notchy/usage`, which will default to zero until a reliable writer exists.

- [ ] **Step 3: Add agent metadata and snapshot types**

Add after the models:

```swift
enum AgentKind {
    case claude
    case codex
}

struct AgentSnapshot {
    let kind: AgentKind
    let name: String
    let status: String
    let project: String
    let lastEventTs: Int
    let usage: AgentUsageModel?
}
```

- [ ] **Step 4: Update `AppDelegate` model properties**

Replace:

```swift
let model = StatusModel()
let usage = UsageModel()
```

With:

```swift
let claudeStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.claude/state/status")
let claudeUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.claude/state/usage")
let codexStatus = AgentStatusModel(path: "\(NSHomeDirectory())/.codex/notchy/status")
let codexUsage = AgentUsageModel(path: "\(NSHomeDirectory())/.codex/notchy/usage")
```

Update the object change subscriptions so both `claudeStatus` and `codexStatus` call `applyVisibility()`.

- [ ] **Step 5: Build after model changes**

Run:

```bash
swiftc -O -target arm64-apple-macos14 -o /tmp/notchy-check main.swift
```

Expected: compile succeeds.

## Task 4: Render Collapsed Newest Agent and Expanded Two-Agent Detail

**Files:**
- Modify: `main.swift`

- [ ] **Step 1: Update `NotchContentView` inputs**

Replace single model/usage inputs with:

```swift
@ObservedObject var claudeStatus: AgentStatusModel
@ObservedObject var claudeUsage: AgentUsageModel
@ObservedObject var codexStatus: AgentStatusModel
@ObservedObject var codexUsage: AgentUsageModel
```

- [ ] **Step 2: Add snapshot helpers**

Add computed properties:

```swift
private var claudeSnapshot: AgentSnapshot {
    AgentSnapshot(kind: .claude, name: "Claude", status: effectiveStatus(for: claudeStatus), project: claudeStatus.project, lastEventTs: claudeStatus.lastEventTs, usage: claudeUsage)
}

private var codexSnapshot: AgentSnapshot {
    AgentSnapshot(kind: .codex, name: "Codex", status: effectiveStatus(for: codexStatus), project: codexStatus.project, lastEventTs: codexStatus.lastEventTs, usage: codexUsage)
}

private var activeSnapshot: AgentSnapshot {
    codexSnapshot.lastEventTs > claudeSnapshot.lastEventTs ? codexSnapshot : claudeSnapshot
}

private func effectiveStatus(for model: AgentStatusModel) -> String {
    if model.status == "waiting" {
        let age = Int(Date().timeIntervalSince1970) - model.lastEventTs
        if age > 3 { return "idle" }
    }
    return model.status
}
```

- [ ] **Step 3: Add a Codex mark view**

Use a compact text mark to avoid adding image assets:

```swift
struct CodexMark: View {
    var body: some View {
        Text("C")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .frame(width: 14, height: 14)
            .background(Circle().fill(Color.white.opacity(0.9)))
    }
}
```

- [ ] **Step 4: Render the active icon in collapsed state**

Replace `ClaudeCrabIcon(size: 14)` with:

```swift
if activeSnapshot.kind == .claude {
    ClaudeCrabIcon(size: 14)
} else {
    CodexMark()
}
```

Make `dotColor` take `activeSnapshot.status`.

- [ ] **Step 5: Replace expanded detail with two agent rows**

Use:

```swift
private var expandedDetail: some View {
    VStack(alignment: .leading, spacing: 10) {
        agentRow(claudeSnapshot, showUsage: true)
        Divider().background(Color.white.opacity(0.12))
        agentRow(codexSnapshot, showUsage: false)
        HStack {
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .padding(.top, 2)
    }
}
```

Add `agentRow`:

```swift
private func agentRow(_ snapshot: AgentSnapshot, showUsage: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
            if snapshot.kind == .claude {
                ClaudeCrabIcon(size: 12)
            } else {
                CodexMark()
                    .scaleEffect(0.86)
            }
            Text(snapshot.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.82))
            if !snapshot.project.isEmpty {
                Text(snapshot.project)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
            Text(snapshot.status)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }

        if showUsage, let usage = snapshot.usage {
            usageRow(label: "5h block", pct: usage.blockPct, reset: usage.blockResetUnix)
            usageRow(label: "This week", pct: usage.weeklyPct, reset: usage.weeklyResetUnix)
        }
    }
}
```

- [ ] **Step 6: Adjust expanded height if needed**

In `rebuild()`, change:

```swift
height: collapsedSize.height + 120
```

To:

```swift
height: collapsedSize.height + 150
```

- [ ] **Step 7: Build after UI changes**

Run:

```bash
swiftc -O -target arm64-apple-macos14 -o /tmp/notchy-check main.swift
```

Expected: compile succeeds.

## Task 5: Documentation and Full Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README intro**

Change the opening description to say Notchy supports Claude Code and Codex, and collapsed mode shows whichever updated most recently.

- [ ] **Step 2: Update requirements**

Add Codex as optional:

```markdown
- Claude Code and/or Codex installed
```

- [ ] **Step 3: Update installer description**

Add bullets:

```markdown
- Install Codex hook script to `~/.codex/notchy/play.sh`
- Enable Codex lifecycle hooks in `~/.codex/config.toml`
- Merge Notchy Codex hook entries into `~/.codex/hooks.json`
```

- [ ] **Step 4: Update caveats**

Add:

```markdown
- **Codex usage bars are not shown yet.** Codex lifecycle hooks provide status updates, but Codex does not expose the same statusline `rate_limits` feed that Claude Code provides.
- **Codex hooks require a restart.** Restart any running Codex CLI session after installing or reconfiguring Notchy.
```

- [ ] **Step 5: Run full build**

Run:

```bash
./build.sh
```

Expected:

```text
Done.
  App: .../build/pkg-root/Applications/Notchy.app
  Pkg: .../build/Notchy.pkg
```

- [ ] **Step 6: Inspect final diff**

Run:

```bash
git diff -- main.swift play.sh codex-play.sh scripts/postinstall build.sh README.md
```

Expected: diff only contains Codex support and related docs.

## Self-Review

- Spec coverage: collapsed newest-agent behavior is covered in Task 4; expanded two-agent rows are covered in Task 4; Codex hook/install setup is covered in Tasks 1 and 2; docs/build verification is covered in Task 5.
- No Codex usage estimator is included because the approved design explicitly avoids fake usage numbers.
- The plan preserves existing Claude behavior by reusing current state files, hook mappings, and usage parsing.

