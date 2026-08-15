#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PREFS_STATE="$CATWAY_STATE_DIR/native-mission-control.tsv"
[[ -r "$PREFS_STATE" ]] || exit 0

while IFS=$'\t' read -r domain key value; do
  if [[ "$value" == "__CATWAY_UNSET__" ]]; then
    if [[ "$domain" == "@currentHost:NSGlobalDomain" ]]; then
      defaults -currentHost delete NSGlobalDomain "$key" >/dev/null 2>&1 || true
    else
      defaults delete "$domain" "$key" >/dev/null 2>&1 || true
    fi
  else
    if [[ "$domain" == "@currentHost:NSGlobalDomain" ]]; then
      defaults -currentHost write NSGlobalDomain "$key" -int "$value"
    else
      defaults write "$domain" "$key" -int "$value"
    fi
  fi
done < "$PREFS_STATE"
killall Dock >/dev/null 2>&1 || true
printf 'Native Mission Control preferences restored.\n'
