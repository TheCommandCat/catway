#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/scripts/lib/common.sh"
BUILD_ROOT="${CATWAY_BUILD_ROOT:-$ROOT/build}"
APP="$BUILD_ROOT/Catway.app"

catway_assert_safe_managed_path "build application" "$APP"

cd "$ROOT"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 0755 "$BIN_DIR/Catway" "$APP/Contents/MacOS/Catway"
ditto "$ROOT/scripts" "$APP/Contents/Resources/scripts"
ditto "$ROOT/integrations" "$APP/Contents/Resources/integrations"
mkdir -p "$APP/Contents/Resources/assets"
install -m 0644 "$ROOT/assets/catway-process.png" "$APP/Contents/Resources/assets/catway-process.png"
install -m 0644 "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"

ICONSET="$BUILD_ROOT/Catway.iconset"
MASTER_ICON="$ROOT/assets/catway-logo.png"
catway_assert_safe_managed_path "icon build directory" "$ICONSET"
rm -rf -- "$ICONSET"
mkdir -p "$ICONSET"
for spec in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'
do
  pixels="${spec%% *}"
  filename="${spec#* }"
  sips -z "$pixels" "$pixels" "$MASTER_ICON" --out "$ICONSET/$filename" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Catway.icns"

chmod +x "$APP/Contents/Resources/scripts/"*.sh "$APP/Contents/Resources/scripts/catway"
chmod +x "$APP/Contents/Resources/integrations/sketchybar/"*.sh
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
