#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Luma.app"
RES="$APP/Contents/Resources"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"

swiftc -O \
  -target arm64-apple-macos12.0 \
  -framework Cocoa \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/Luma"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/assets/Luma.icns" ] && cp "$ROOT/assets/Luma.icns" "$RES/Luma.icns"
[ -f "$ROOT/assets/DonateQR.png" ] && cp "$ROOT/assets/DonateQR.png" "$RES/DonateQR.png"
for lproj in "$ROOT"/Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$RES/"
done

IDENTITY="${CODESIGN_IDENTITY:-Wangfou Dev Signing}"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --sign - --timestamp=none "$APP"

echo "Built: $APP"
