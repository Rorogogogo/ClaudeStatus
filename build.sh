#!/bin/bash
# Build ClaudeStatus.app and ClaudeStatus.pkg.
#
# Requirements:
#   - Xcode Command Line Tools (`xcode-select --install`)
#   - macOS 14+ (Sonoma) — needed for safeAreaInsets / auxiliaryTopRightArea APIs
#
# Outputs:
#   build/ClaudeStatus.app  — the standalone app bundle
#   build/ClaudeStatus.pkg  — the macOS installer

set -euo pipefail

VERSION="1.0.0"
IDENTIFIER="com.claudestatus.app"
APP_NAME="ClaudeStatus"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
PKG_ROOT="$BUILD/pkg-root"
APP_PATH="$PKG_ROOT/Applications/$APP_NAME.app"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$PKG_ROOT/Applications" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

echo "[1/4] Compiling main.swift..."
swiftc -O -target arm64-apple-macos14 \
  -o "$APP_PATH/Contents/MacOS/$APP_NAME" \
  "$ROOT/main.swift"

echo "[2/4] Writing Info.plist..."
cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$IDENTIFIER</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "[3/4] Staging postinstall and play.sh into pkg payload..."
# play.sh ships inside the .app's Resources so the postinstall can copy it
# into the user's home directory.
cp "$ROOT/play.sh" "$APP_PATH/Contents/Resources/play.sh"
chmod +x "$APP_PATH/Contents/Resources/play.sh"

# Strip quarantine attribute so the locally-built .app doesn't trip Gatekeeper
# for the person doing the build.
xattr -cr "$APP_PATH" 2>/dev/null || true

mkdir -p "$BUILD/scripts"
cp "$ROOT/scripts/postinstall" "$BUILD/scripts/postinstall"
chmod +x "$BUILD/scripts/postinstall"

echo "[4/4] Building .pkg..."
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$BUILD/scripts" \
  --identifier "$IDENTIFIER" \
  --install-location "/" \
  --version "$VERSION" \
  "$BUILD/$APP_NAME.pkg"

echo ""
echo "Done."
echo "  App: $APP_PATH"
echo "  Pkg: $BUILD/$APP_NAME.pkg"
