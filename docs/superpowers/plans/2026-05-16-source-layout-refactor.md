# Notchy Source Layout Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split Notchy's Swift source into focused files without changing runtime behavior or package output.

**Architecture:** Keep the existing `build.sh` and `swiftc` pipeline. Move top-level Swift declarations into `Sources/Notchy` files grouped by responsibility, then compile all source files together.

**Tech Stack:** Swift, SwiftUI, AppKit, Combine, shell `build.sh`, `swiftc`, `pkgbuild`.

---

### Task 1: Create Source Folders

**Files:**
- Create: `Sources/Notchy/Models`
- Create: `Sources/Notchy/Views/Icons`
- Create: `Sources/Notchy/Windowing`

- [ ] **Step 1: Create folders**

Run:

```bash
mkdir -p Sources/Notchy/Models Sources/Notchy/Views/Icons Sources/Notchy/Windowing
```

Expected: command exits 0.

### Task 2: Split Swift Declarations

**Files:**
- Create: `Sources/Notchy/Models/AgentStatusModel.swift`
- Create: `Sources/Notchy/Models/AgentUsageModel.swift`
- Create: `Sources/Notchy/Models/GitHubRepoStatsModel.swift`
- Create: `Sources/Notchy/Models/AgentKind.swift`
- Create: `Sources/Notchy/Models/AgentSnapshot.swift`
- Create: `Sources/Notchy/Views/UsageBar.swift`
- Create: `Sources/Notchy/Windowing/NSScreen+Notch.swift`
- Create: `Sources/Notchy/Windowing/NotchShape.swift`
- Create: `Sources/Notchy/Views/Icons/ClaudeCrabIcon.swift`
- Create: `Sources/Notchy/Views/Icons/CodexMark.swift`
- Create: `Sources/Notchy/Views/NotchContentView.swift`
- Create: `Sources/Notchy/Windowing/NotchPanel.swift`
- Create: `Sources/Notchy/AppDelegate.swift`
- Create: `Sources/Notchy/main.swift`
- Delete: `main.swift`

- [ ] **Step 1: Move each top-level declaration into the matching file**

Preserve declaration bodies exactly except for adding needed imports at the top of each file.

- [ ] **Step 2: Add imports**

Use `import AppKit`, `import Combine`, and `import SwiftUI` only where needed by that file.

### Task 3: Update Build Script

**Files:**
- Modify: `build.sh`

- [ ] **Step 1: Replace the single-file compile input**

Change the compile step from `"$ROOT/main.swift"` to an array populated by:

```bash
SWIFT_SOURCES=()
while IFS= read -r source_file; do
  SWIFT_SOURCES+=("$source_file")
done < <(find "$ROOT/Sources/Notchy" -name '*.swift' -print | sort)
```

Then pass `"${SWIFT_SOURCES[@]}"` to `swiftc`.

### Task 4: Verify Package Build

**Files:**
- Verify generated output: `build/Notchy.pkg`

- [ ] **Step 1: Run build**

Run:

```bash
./build.sh
```

Expected: command exits 0 and prints the app and pkg paths.
