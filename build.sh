#!/bin/bash
# Build Notchy.app and Notchy.pkg.
#
# Requirements:
#   - Xcode Command Line Tools (`xcode-select --install`)
#   - macOS 14+ (Sonoma) — needed for safeAreaInsets / auxiliaryTopRightArea APIs
#
# Outputs:
#   build/Notchy.app  — the standalone app bundle
#   build/Notchy.pkg  — the macOS installer

set -euo pipefail

VERSION="1.3.0"
IDENTIFIER="com.notchy.app"
APP_NAME="Notchy"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
PKG_ROOT="$BUILD/pkg-root"
APP_PATH="$PKG_ROOT/Applications/$APP_NAME.app"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$PKG_ROOT/Applications" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

echo "[1/5] Generating icons..."
"$ROOT/scripts/build-icons.sh"
cp "$BUILD/icons/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$ROOT/assets/codex.svg" "$APP_PATH/Contents/Resources/codex.svg"
cp "$ROOT/assets/github.svg" "$APP_PATH/Contents/Resources/github.svg"

GITHUB_REPO="Rorogogogo/Notchy"
GITHUB_URL="$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null || true)"
case "$GITHUB_URL" in
  https://github.com/*)
    GITHUB_REPO="${GITHUB_URL#https://github.com/}"
    GITHUB_REPO="${GITHUB_REPO%.git}"
    ;;
  git@github.com:*)
    GITHUB_REPO="${GITHUB_URL#git@github.com:}"
    GITHUB_REPO="${GITHUB_REPO%.git}"
    ;;
esac
GITHUB_WEB_URL="https://github.com/$GITHUB_REPO"
GITHUB_STARS="$(
  curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$GITHUB_REPO" 2>/dev/null |
    sed -n 's/.*"stargazers_count": \([0-9][0-9]*\).*/\1/p' |
    head -n 1
)"

printf '%s\n' "$GITHUB_REPO" > "$APP_PATH/Contents/Resources/github-repo.txt"
printf '%s\n' "$GITHUB_WEB_URL" > "$APP_PATH/Contents/Resources/github-url.txt"
printf '%s\n' "${GITHUB_STARS:-—}" > "$APP_PATH/Contents/Resources/github-stars.txt"

echo "[2/5] Compiling Swift sources..."
SWIFT_SOURCES=()
while IFS= read -r source_file; do
  SWIFT_SOURCES+=("$source_file")
done < <(find "$ROOT/Sources/Notchy" -name '*.swift' -print | sort)

swiftc -O -target arm64-apple-macos14 \
  -o "$APP_PATH/Contents/MacOS/$APP_NAME" \
  "${SWIFT_SOURCES[@]}"

echo "[3/5] Writing Info.plist..."
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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "[4/5] Staging postinstall + hook scripts into pkg scripts dir..."
# Keep a copy in the .app Resources/ for users who want to inspect it.
cp "$ROOT/play.sh" "$APP_PATH/Contents/Resources/play.sh"
chmod +x "$APP_PATH/Contents/Resources/play.sh"

# Strip quarantine on the locally-built .app
xattr -cr "$APP_PATH" 2>/dev/null || true

# The pkg's scripts dir is the postinstall's working directory at install time,
# so anything we drop here is reachable via $PWD/<name> from postinstall.
mkdir -p "$BUILD/scripts"
cp "$ROOT/scripts/postinstall" "$BUILD/scripts/postinstall"
cp "$ROOT/play.sh"             "$BUILD/scripts/play.sh"
cp "$ROOT/codex-play.sh"       "$BUILD/scripts/codex-play.sh"
cp "$ROOT/codex-usage.sh"      "$BUILD/scripts/codex-usage.sh"
cp "$ROOT/gemini-play.sh"      "$BUILD/scripts/gemini-play.sh"
chmod +x "$BUILD/scripts/postinstall" "$BUILD/scripts/play.sh" "$BUILD/scripts/codex-play.sh" "$BUILD/scripts/codex-usage.sh" "$BUILD/scripts/gemini-play.sh"

echo "[5/5] Building .pkg..."
codesign --force --deep --sign - "$APP_PATH"

# Generate a component plist so we can disable bundle relocation
# (otherwise macOS Installer may write the .app to wherever an existing
# copy lives, instead of /Applications).
COMPONENT_PLIST="$BUILD/component.plist"
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST" 2>/dev/null || true

pkgbuild \
  --root "$PKG_ROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --scripts "$BUILD/scripts" \
  --identifier "$IDENTIFIER" \
  --install-location "/" \
  --version "$VERSION" \
  "$BUILD/$APP_NAME.pkg"

# Ad-hoc sign the .pkg itself
codesign --force --sign - "$BUILD/$APP_NAME.pkg" 2>/dev/null || true

echo ""
echo "Done."
echo "  App: $APP_PATH"
echo "  Pkg: $BUILD/$APP_NAME.pkg"
