#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DualAudio"
BUNDLE_ID="com.dualaudio.app"
DEST_DIR="$HOME/Applications"
APP_BUNDLE="$DEST_DIR/$APP_NAME.app"

echo "Building release binary..."
swift build -c release

echo "Assembling $APP_BUNDLE..."
mkdir -p "$DEST_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

echo "Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done. Installed at $APP_BUNDLE"
