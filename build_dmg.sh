#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DualAudio"
APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
OUTPUT_DMG="$(pwd)/$APP_NAME.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found at $APP_BUNDLE — run ./build_app.sh first."
    exit 1
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Staging DMG contents..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$OUTPUT_DMG"

echo "Creating $OUTPUT_DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DMG"

echo "Done: $OUTPUT_DMG"
