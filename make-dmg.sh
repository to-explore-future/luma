#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Luma.app"
DIST="$ROOT/dist"
DMG="$DIST/Luma-2.1.1.dmg"
"$ROOT/build.sh"
mkdir -p "$DIST"; rm -rf "$DIST/.stage" "$DMG"; mkdir -p "$DIST/.stage"
cp -R "$APP" "$DIST/.stage/Luma.app"
ln -s /Applications "$DIST/.stage/Applications"
hdiutil create -volname "Luma" -srcfolder "$DIST/.stage" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/.stage"
echo "DMG: $DMG"; ls -lh "$DMG"
