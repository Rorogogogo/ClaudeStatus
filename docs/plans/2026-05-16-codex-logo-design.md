# Codex Logo Design

## Goal

Replace Notchy's temporary Codex `C` badge with the real Codex glyph.

## Approach

Bundle the Codex mono SVG from LobeHub's MIT-licensed icon package as
`assets/codex.svg`. Load it at runtime from `Bundle.main` with `NSImage`, mark
it as a template image, and render it white inside the black Notchy pill. Keep a
text fallback in case the resource is missing.

## Verification

Build the app, verify `codex.svg` is staged into app resources, and relaunch
Notchy from the rebuilt app bundle.
