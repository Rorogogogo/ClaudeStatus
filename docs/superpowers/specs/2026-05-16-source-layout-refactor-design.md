# Notchy Source Layout Refactor Design

## Goal

Split the current single-file Swift app into focused source files while preserving the existing build system, app bundle output, installer output, and runtime behavior.

## Scope

- Keep `build.sh` as the packaging entrypoint.
- Keep `swiftc` as the compiler invocation.
- Keep producing `build/Notchy.app` and `build/Notchy.pkg`.
- Move Swift app source from `main.swift` into `Sources/Notchy`.
- Do not change app behavior, bundle metadata, scripts, resources, package structure, signing, or installer logic.

## Structure

Use a simple feature-oriented layout:

```text
Sources/Notchy/
  main.swift
  AppDelegate.swift
  Models/
    AgentKind.swift
    AgentSnapshot.swift
    AgentStatusModel.swift
    AgentUsageModel.swift
    GitHubRepoStatsModel.swift
  Views/
    NotchContentView.swift
    UsageBar.swift
    Icons/
      ClaudeCrabIcon.swift
      CodexMark.swift
  Windowing/
    NSScreen+Notch.swift
    NotchPanel.swift
    NotchShape.swift
```

## Build

Update `build.sh` so the compile step passes every Swift file under `Sources/Notchy` to `swiftc`. The output executable path remains `build/pkg-root/Applications/Notchy.app/Contents/MacOS/Notchy`. Keep the entrypoint in `Sources/Notchy/main.swift` so top-level Swift code is compiled using Swift's standard entrypoint filename.

## Verification

Run `./build.sh` after the split. A successful build proves the split preserves Swift type visibility and produces the same package artifact path.
