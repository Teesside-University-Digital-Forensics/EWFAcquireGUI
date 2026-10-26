#!/bin/bash
# Builds "EWF Acquire GUI.app" as a native Apple Silicon (arm64) app.
# Requirements: Apple Silicon Mac, macOS 13+, Xcode or Command Line Tools (xcode-select --install).
#
# Options (environment variables):
#   ARCH=arm64            target architecture (default). ARCH=universal builds arm64 + x86_64 (needs full Xcode).
#   DMG=1                 also produce EWFAcquireGUI-v<version>-<build>.dmg
#   SIGN_ID="Developer ID Application: Name (TEAMID)"   sign with your identity instead of ad-hoc
set -euo pipefail
cd "$(dirname "$0")"

APP="EWF Acquire GUI.app"
NAME="EWFAcquireGUI"
ARCH="${ARCH:-arm64}"

# Version comes from AppInfo.swift (single source of truth)
INFO_SWIFT="Sources/EWFAcquireGUI/AppInfo.swift"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "$INFO_SWIFT")"
BUILD="$(sed -n 's/.*static let build = "\(.*\)".*/\1/p' "$INFO_SWIFT")"
if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  echo "Could not read version/build from $INFO_SWIFT" >&2; exit 1
fi
echo "Building EWF Acquire GUI v$VERSION ($BUILD)"

if [ "$ARCH" = "universal" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  REQUIRE_NATIVE=""
else
  ARCH_FLAGS=(--arch "$ARCH")
  REQUIRE_NATIVE="<key>LSRequiresNativeExecution</key><true/>"
fi

swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$NAME" "$APP/Contents/MacOS/$NAME"
strip -x "$APP/Contents/MacOS/$NAME" 2>/dev/null || true
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>EWF Acquire GUI</string>
    <key>CFBundleDisplayName</key><string>EWF Acquire GUI</string>
    <key>CFBundleIdentifier</key><string>local.ewfacquire.gui</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    $REQUIRE_NATIVE
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "${SIGN_ID:--}" "$APP"

echo
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/$NAME")"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1

if [ "${DMG:-0}" = "1" ]; then
  rm -rf dmg_staging
  mkdir dmg_staging
  cp -R "$APP" dmg_staging/
  ln -s /Applications dmg_staging/Applications
  DMG_NAME="EWFAcquireGUI-v$VERSION-$BUILD.dmg"
  rm -f "$DMG_NAME"
  hdiutil create -volname "EWF Acquire GUI" -srcfolder dmg_staging -ov -format UDZO "$DMG_NAME" >/dev/null
  rm -rf dmg_staging
  echo "DMG:   $(pwd)/$DMG_NAME"
fi

echo "Built: $(pwd)/$APP"
echo "Run:   open \"$APP\""
