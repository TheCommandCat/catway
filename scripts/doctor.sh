#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

SUMMARY=false
[[ "${1:-}" == "--summary" ]] && SUMMARY=true
required_failures=0
warnings=0
checks=()

check_command() {
  local name="$1"
  local required="$2"
  local override="${3:-}"
  local found
  if found="$(catway_find_executable "$name" "$override" 2>/dev/null)"; then
    checks+=("ok:$name:$found")
  elif [[ "$required" == "true" ]]; then
    checks+=("fail:$name:not found")
    ((required_failures += 1))
  else
    checks+=("warn:$name:not installed (optional)")
    ((warnings += 1))
  fi
}

check_command yabai true "${CATWAY_YABAI:-}"
check_command jq true "${CATWAY_JQ:-}"
check_command skhd false "${CATWAY_SKHD:-}"
check_command sketchybar false "${CATWAY_SKETCHYBAR:-}"
if [[ -d /Applications/Hammerspoon.app ]]; then
  checks+=("ok:Hammerspoon:/Applications/Hammerspoon.app")
else
  checks+=("warn:Hammerspoon:not installed; four-finger gestures unavailable")
  ((warnings += 1))
fi

if [[ -d "$CATWAY_APP" ]]; then
  checks+=("ok:Catway app:$CATWAY_APP")
else
  checks+=("fail:Catway app:not installed at $CATWAY_APP")
  ((required_failures += 1))
fi

if catway_process_pid >/dev/null 2>&1; then
  checks+=("ok:wheel daemon:running")
else
  checks+=("warn:wheel daemon:not running; first invocation will be slower")
  ((warnings += 1))
fi

integration_check() {
  local name="$1"
  local file="$2"
  if [[ -f "$file" ]] && grep -Eq "^(#|--) >>> Catway:$name >>>" "$file"; then
    checks+=("ok:$name integration:loaded")
  else
    checks+=("warn:$name integration:not loaded")
    ((warnings += 1))
  fi
}

integration_check hammerspoon "${CATWAY_HAMMERSPOON_CONFIG:-$HOME/.hammerspoon/init.lua}"
integration_check skhd "${CATWAY_SKHD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/skhd/skhdrc}"
integration_check yabai "${CATWAY_YABAI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/yabai/yabairc}"
integration_check sketchybar "${CATWAY_SKETCHYBAR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar/sketchybarrc}"

check_skhd_parser() {
  local skhd error_log before_size new_errors
  skhd="$(catway_find_executable skhd "${CATWAY_SKHD:-}" 2>/dev/null)" || return 0
  error_log="${CATWAY_SKHD_ERROR_LOG:-/tmp/skhd_${USER:-$(id -un)}.err.log}"
  before_size=0
  [[ -f "$error_log" ]] && before_size="$(stat -f%z "$error_log" 2>/dev/null || printf 0)"
  if ! "$skhd" --reload >/dev/null 2>&1; then
    checks+=("warn:skhd config:reload unavailable; is skhd running?")
    ((warnings += 1))
    return 0
  fi
  sleep 0.15
  new_errors=""
  if [[ -f "$error_log" ]]; then
    new_errors="$(tail -c +$((before_size + 1)) "$error_log" 2>/dev/null || true)"
  fi
  if printf '%s' "$new_errors" | grep -Eq 'expected decl|could not open file .*load directive'; then
    checks+=("fail:skhd config:parser rejected the loaded config")
    ((required_failures += 1))
  else
    checks+=("ok:skhd config:reload parsed")
  fi
}

check_skhd_parser

if $SUMMARY; then
  if (( required_failures == 0 )); then
    printf 'Catway ready'
    (( warnings > 0 )) && printf ' · %d optional warning(s)' "$warnings"
    printf '\n'
  else
    printf 'Catway needs attention · %d required check(s) failed\n' "$required_failures"
  fi
else
  printf 'Catway doctor\n\n'
  for check in "${checks[@]}"; do
    IFS=: read -r status name detail <<< "$check"
    case "$status" in
      ok) symbol='[OK]' ;;
      warn) symbol='[!!]' ;;
      *) symbol='[FAIL]' ;;
    esac
    printf '%-6s %-24s %s\n' "$symbol" "$name" "$detail"
  done
  printf '\nCatway never edits config outside its marked include blocks.\n'
  printf 'Accessibility must be enabled for Hammerspoon and yabai in System Settings.\n'
fi
exit "$required_failures"
