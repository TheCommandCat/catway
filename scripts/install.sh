#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/scripts/lib/common.sh"
PREFIX="${CATWAY_PREFIX:-$HOME/.local}"
CONFIG_HOME="${CATWAY_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/catway}"
SHARE="$PREFIX/share/catway"
APP_DESTINATION="${CATWAY_APP:-$HOME/Applications/Catway.app}"
CLI_DESTINATION="$PREFIX/bin/catway"
NO_OPEN=false
NO_START=false
for argument in "$@"; do
  case "$argument" in
    --no-open) NO_OPEN=true ;;
    --no-start) NO_START=true ;;
    *) printf 'Unknown installer option: %s\n' "$argument" >&2; exit 64 ;;
  esac
done

catway_assert_safe_managed_path "application destination" "$APP_DESTINATION"
catway_assert_safe_managed_path "shared files" "$SHARE"
catway_assert_safe_managed_path "configuration" "$CONFIG_HOME"

for command in swift codesign ditto jq yabai; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Catway installer: missing required command: %s\n' "$command" >&2
    exit 127
  }
done

APP_SOURCE="$($ROOT/scripts/build-app.sh | tail -n 1)"
mkdir -p "$PREFIX/bin" "$PREFIX/share" "$HOME/Applications" "$CONFIG_HOME/state/upgrades"

if [[ -e "$CLI_DESTINATION" && ! -L "$CLI_DESTINATION" ]]; then
  printf 'Catway installer will not overwrite non-symlink: %s\n' "$CLI_DESTINATION" >&2
  exit 73
fi

if [[ -d "$APP_DESTINATION" ]]; then
  timestamp="$(date +%Y%m%d-%H%M%S)"
  ditto "$APP_DESTINATION" "$CONFIG_HOME/state/upgrades/Catway-$timestamp.app"
fi

if [[ -x "$CLI_DESTINATION" ]]; then
  CATWAY_CONFIG_HOME="$CONFIG_HOME" CATWAY_APP="$APP_DESTINATION" "$CLI_DESTINATION" stop || true
fi

STAGED_APP="$HOME/Applications/.Catway.app.installing.$$"
rm -rf -- "$STAGED_APP"
ditto "$APP_SOURCE" "$STAGED_APP"
rm -rf -- "$APP_DESTINATION"
mv "$STAGED_APP" "$APP_DESTINATION"

rm -rf -- "$SHARE"
mkdir -p "$SHARE"
ditto "$ROOT/scripts" "$SHARE/scripts"
ditto "$ROOT/integrations" "$SHARE/integrations"
mkdir -p "$SHARE/assets"
install -m 0644 "$ROOT/assets/catway-process.png" "$SHARE/assets/catway-process.png"
ln -sfn "$SHARE/scripts/catway" "$CLI_DESTINATION"

CATWAY_PREFIX="$PREFIX" CATWAY_CONFIG_HOME="$CONFIG_HOME" CATWAY_APP="$APP_DESTINATION" \
  "$CLI_DESTINATION" install-integrations
CATWAY_PREFIX="$PREFIX" CATWAY_CONFIG_HOME="$CONFIG_HOME" CATWAY_APP="$APP_DESTINATION" \
  "$CLI_DESTINATION" sync-settings
printf '0.1.0\n' > "$CONFIG_HOME/state/installed-version"

if ! $NO_START; then
  CATWAY_PREFIX="$PREFIX" CATWAY_CONFIG_HOME="$CONFIG_HOME" CATWAY_APP="$APP_DESTINATION" \
    "$CLI_DESTINATION" daemon
fi
if ! $NO_OPEN; then
  open -na "$APP_DESTINATION"
fi

printf '\nCatway installed at %s\n' "$APP_DESTINATION"
printf 'Run: %s doctor\n' "$CLI_DESTINATION"
printf 'If gestures do not respond, grant Accessibility to Hammerspoon and yabai.\n'
