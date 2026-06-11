#!/bin/bash
# Assemble TokenBar.app from the SwiftPM release build.
#
#   scripts/bundle.sh [marketing-version] [build-number]
#
# Defaults: 1.0.0-beta.1 / 100. Run from the repo root. The beta channel uses
# its own bundle id (com.nyanako.tokenbar.beta) so it can run alongside the
# Tauri stable app without fighting over LaunchServices/defaults; the id
# switches to com.nyanako.tokenbar at the stable 1.0.0 release (Phase 10).
set -euo pipefail

VERSION="${1:-1.0.0-beta.1}"
BUILD_NUMBER="${2:-100}"
BUNDLE_ID="${BUNDLE_ID:-com.nyanako.tokenbar.beta}"
# The beta installs alongside the stable Tauri TokenBar.app, so the bundle
# carries a distinct name to avoid the /Applications file collision.
APP_NAME="${APP_DISPLAY:-TokenBar Beta}"
OUT_DIR="dist"
APP="$OUT_DIR/$APP_NAME.app"

echo "==> building release binaries"
cargo build --release
swift build -c release

echo "==> assembling $APP ($VERSION, build $BUILD_NUMBER, $BUNDLE_ID)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/TokenBar "$APP/Contents/MacOS/TokenBar"
# SwiftPM resource bundle (animation frames, agent icons).
cp -R .build/release/TokenBar_TokenBar.bundle "$APP/Contents/Resources/"
# Brand icon, shared with the Tauri app.
if [ -f assets/icon.icns ]; then
  cp assets/icon.icns "$APP/Contents/Resources/icon.icns"
fi
# Sparkle framework (SPM binary artifact).
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TokenBar</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
    <key>SUEnableInstallerLauncherService</key>
    <false/>
    <key>SUPublicEDKey</key>
    <string>EzyeEi0NEwYK/pYigOPVClXmbmnHXXBEHM7r2uy8GYs=</string>
    <!-- raw main-branch URL: GitHub's releases/latest/download excludes
         prerelease-flagged releases, which would break the beta channel -->
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/Nanako0129/TokenBar-Native/main/appcast.xml</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
