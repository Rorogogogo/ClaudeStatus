# Codex Usage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Codex usage bars to Notchy from Codex session `rate_limits` events.

**Architecture:** A new `codex-usage.sh` helper parses recent Codex JSONL session files and writes the existing Notchy usage format to `~/.codex/notchy/usage`. `codex-play.sh` invokes the helper after hook events, and `main.swift` renders Codex usage with the existing `AgentUsageModel`.

**Tech Stack:** Bash, Python 3, SwiftUI/AppKit, macOS Installer scripts.

---

### Task 1: Codex Usage Parser

**Files:**
- Create: `codex-usage.sh`
- Create: `scripts/test-codex-usage.sh`

**Step 1: Write the failing test**

Create a shell test that builds a temporary `HOME`, writes synthetic Codex JSONL files under `$HOME/.codex/sessions`, runs `./codex-usage.sh`, and expects `~/.codex/notchy/usage` to contain the latest rate-limit values.

**Step 2: Run the test to verify it fails**

Run: `scripts/test-codex-usage.sh`

Expected: FAIL because `codex-usage.sh` does not exist yet.

**Step 3: Implement `codex-usage.sh`**

The helper should:
- scan newest `~/.codex/sessions/**/*.jsonl`
- parse newest valid `token_count` event containing `rate_limits`
- map primary to 5h and secondary to weekly
- write `<primary_pct>\t<primary_reset>\t<secondary_pct>\t<secondary_reset>` to `~/.codex/notchy/usage`

**Step 4: Run the test to verify it passes**

Run: `scripts/test-codex-usage.sh`

Expected: PASS.

### Task 2: Installer and Hook Wiring

**Files:**
- Modify: `codex-play.sh`
- Modify: `build.sh`
- Modify: `scripts/postinstall`

**Step 1: Make `codex-play.sh` invoke usage helper**

After writing status, call `~/.codex/notchy/usage.sh` in the background if executable.

**Step 2: Stage and install `codex-usage.sh`**

Copy `codex-usage.sh` into package scripts in `build.sh`, and copy it to `~/.codex/notchy/usage.sh` in `scripts/postinstall`.

**Step 3: Verify shell syntax**

Run: `bash -n codex-play.sh codex-usage.sh scripts/postinstall build.sh scripts/test-codex-usage.sh`

Expected: no output, exit 0.

### Task 3: Render Codex Usage

**Files:**
- Modify: `main.swift`
- Modify: `README.md`

**Step 1: Enable Codex usage row**

Change the Codex expanded row to pass `showUsage: true`.

**Step 2: Update docs**

Replace the caveat saying Codex usage bars are not shown with a caveat that Codex usage is read from local session `rate_limits` and appears after Codex has emitted a token-count event.

**Step 3: Verify build**

Run: `./build.sh`

Expected: package build succeeds, with only existing Swift actor-isolation warnings if any.
