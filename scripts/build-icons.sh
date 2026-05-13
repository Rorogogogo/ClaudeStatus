#!/bin/bash
# Generates AppIcon.icns (for the .app bundle) and logo.png (for the README).
# Driven by gen-icon.swift, which renders the crab at any pixel size.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/build/icons"
ICONSET="$OUT_DIR/AppIcon.iconset"

mkdir -p "$ICONSET"

declare -a sizes=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
  size="${entry%%:*}"
  name="${entry##*:}"
  swift "$ROOT/gen-icon.swift" "$size" "$ICONSET/$name" > /dev/null
done

iconutil --convert icns "$ICONSET" --output "$OUT_DIR/AppIcon.icns"

# 512x512 PNG for the README
mkdir -p "$ROOT/assets"
swift "$ROOT/gen-icon.swift" 512 "$ROOT/assets/logo.png" > /dev/null

echo "wrote $OUT_DIR/AppIcon.icns"
echo "wrote $ROOT/assets/logo.png"
