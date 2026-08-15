#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PURGE=false
case "${1:-}" in
  "") ;;
  --purge) PURGE=true ;;
  *) printf 'Usage: uninstall.sh [--purge]\n' >&2; exit 64 ;;
esac

SHARE_PATH="$CATWAY_PREFIX/share/catway"
catway_assert_safe_managed_path "application destination" "$CATWAY_APP"
catway_assert_safe_managed_path "shared files" "$SHARE_PATH"
catway_assert_safe_managed_path "configuration" "$CATWAY_CONFIG_HOME"

"$CATWAY_SHARE/scripts/catway" stop || true
"$CATWAY_SHARE/scripts/catway" bar-clean || true
"$CATWAY_SHARE/scripts/manage-integrations.sh" uninstall
"$CATWAY_SHARE/scripts/restore-native.sh"

CLI_PATH="$CATWAY_PREFIX/bin/catway"
if [[ -L "$CLI_PATH" && "$(readlink "$CLI_PATH")" == "$SHARE_PATH/scripts/catway" ]]; then
  rm -- "$CLI_PATH"
fi
rm -rf -- "$CATWAY_APP" "$SHARE_PATH"

if $PURGE; then
  rm -rf -- "$CATWAY_CONFIG_HOME"
  printf 'Catway and its saved settings were removed.\n'
else
  printf 'Catway was removed. Settings and backups remain at %s\n' "$CATWAY_CONFIG_HOME"
fi
