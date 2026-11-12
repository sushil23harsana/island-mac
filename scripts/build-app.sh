#!/bin/bash
# Builds build/Island.app (and optionally build/Island.dmg).
# Usage: scripts/build-app.sh [--dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary (Apple silicon + Intel) when possible, otherwise native only.
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN=".build/apple/Products/Release/Island"
else
    swift build -c release
    BIN=".build/release/Island"
fi

APP="build/Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Island"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS will run it locally.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Island"))"

if [[ "${1:-}" == "--dmg" ]]; then
    rm -f build/Island.dmg
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname Island -srcfolder "$STAGE" -ov -format UDZO build/Island.dmg >/dev/null
    rm -rf "$STAGE"
    echo "Built build/Island.dmg"
fi
