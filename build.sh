#!/usr/bin/env bash
# build.sh — builds NetworkWatch.app
# Usage: ./build.sh [--release]
#   --release   compile optimised (slower build, smaller/faster binary)
#   (default)   compile debug (faster build)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="NetworkWatch"
APP_BUNDLE="$SCRIPT_DIR/${APP_NAME}.app"
SWIFT_DIR="$SCRIPT_DIR/swift-app"

BUILD_CONFIG="debug"
[[ "${1:-}" == "--release" ]] && BUILD_CONFIG="release"

echo "Building Swift app (${BUILD_CONFIG})..."
cd "$SWIFT_DIR"
if [[ "$BUILD_CONFIG" == "release" ]]; then
    swift build -c release 2>&1
    BINARY="$SWIFT_DIR/.build/release/$APP_NAME"
else
    swift build 2>&1
    BINARY="$SWIFT_DIR/.build/debug/$APP_NAME"
fi
cd "$SCRIPT_DIR"

echo "Assembling ${APP_NAME}.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Daemon + credentials
cp "$SCRIPT_DIR/network-watchd" "$APP_BUNDLE/Contents/Resources/network-watchd"
chmod +x "$APP_BUNDLE/Contents/Resources/network-watchd"
cp "$SCRIPT_DIR/.env" "$APP_BUNDLE/Contents/Resources/.env"

# App icon
if [[ -f "$SWIFT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$SWIFT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>NetworkWatch</string>
    <key>CFBundleIdentifier</key>      <string>com.networkwatch.app</string>
    <key>CFBundleName</key>            <string>NetworkWatch</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
</dict>
</plist>
EOF

# Ad-hoc codesign (required for macOS to run unsigned apps without quarantine issues)
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null && echo "Codesigned (ad-hoc)." || echo "Codesign skipped."

echo ""
echo "Done: $APP_BUNDLE"
echo ""
echo "To distribute: zip -r NetworkWatch.zip NetworkWatch.app"
echo "Recipient: unzip, right-click → Open the first time (Gatekeeper bypass for unsigned apps)."
