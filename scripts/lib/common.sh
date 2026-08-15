#!/usr/bin/env bash

set -euo pipefail

catway_resolve_source() {
  local source_path="$1"
  local source_dir
  while [[ -L "$source_path" ]]; do
    source_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
    source_path="$(readlink "$source_path")"
    [[ "$source_path" = /* ]] || source_path="$source_dir/$source_path"
  done
  cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd
}

CATWAY_SCRIPT_DIR="$(catway_resolve_source "${BASH_SOURCE[0]}")"
if [[ -d "$CATWAY_SCRIPT_DIR/../../integrations" ]]; then
  CATWAY_DEFAULT_SHARE="$(cd "$CATWAY_SCRIPT_DIR/../.." && pwd)"
elif [[ -d "$CATWAY_SCRIPT_DIR/../integrations" ]]; then
  CATWAY_DEFAULT_SHARE="$(cd "$CATWAY_SCRIPT_DIR/.." && pwd)"
else
  CATWAY_DEFAULT_SHARE="$(cd "$CATWAY_SCRIPT_DIR/../.." && pwd)"
fi
CATWAY_SHARE="${CATWAY_SHARE:-$CATWAY_DEFAULT_SHARE}"
CATWAY_CONFIG_HOME="${CATWAY_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/catway}"
CATWAY_SETTINGS_FILE="${CATWAY_SETTINGS_FILE:-$CATWAY_CONFIG_HOME/settings.json}"
CATWAY_STATE_DIR="${CATWAY_STATE_DIR:-$CATWAY_CONFIG_HOME/state}"
CATWAY_APP="${CATWAY_APP:-$HOME/Applications/Catway.app}"
CATWAY_PREFIX="${CATWAY_PREFIX:-$HOME/.local}"
CATWAY_TMPDIR="${CATWAY_TMPDIR:-${TMPDIR:-/tmp}}"
CATWAY_VISIBLE_MARKER="${CATWAY_TMPDIR%/}/catway-visible"
CATWAY_PID_FILE="${CATWAY_TMPDIR%/}/catway.pid"

catway_assert_safe_managed_path() {
  local label="$1"
  local path="$2"
  local normalized
  normalized="/${path#/}/"

  if [[ -z "$path" || "$path" != /* || "$path" == *$'\n'* ]]; then
    printf 'Catway: refusing unsafe %s path: %q\n' "$label" "$path" >&2
    return 64
  fi
  case "$path" in
    /|/tmp|/private/tmp|/var|/private/var|/Users|/Applications|/Library|/System|/opt|/usr|/bin|/sbin|\
    "$HOME"|"$HOME/"|"$HOME/Applications"|"$HOME/Applications/"|"$HOME/.config"|"$HOME/.config/"|\
    "$CATWAY_PREFIX"|"$CATWAY_PREFIX/")
      printf 'Catway: refusing broad %s path: %s\n' "$label" "$path" >&2
      return 64
      ;;
  esac
  case "$normalized" in
    */../*|*/./*)
      printf 'Catway: refusing non-normalized %s path: %s\n' "$label" "$path" >&2
      return 64
      ;;
  esac
}

catway_find_executable() {
  local name="$1"
  local override="${2:-}"
  local candidate
  if [[ -n "$override" && -x "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if candidate="$(command -v "$name" 2>/dev/null)" && [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name" "/usr/bin/$name" "/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

catway_require() {
  local name="$1"
  local override="${2:-}"
  local result
  if ! result="$(catway_find_executable "$name" "$override")"; then
    printf 'Catway: required command not found: %s\n' "$name" >&2
    return 127
  fi
  printf '%s\n' "$result"
}

catway_yabai() {
  catway_require yabai "${CATWAY_YABAI:-}"
}

catway_jq() {
  catway_require jq "${CATWAY_JQ:-}"
}

catway_sketchybar() {
  catway_find_executable sketchybar "${CATWAY_SKETCHYBAR:-}"
}

catway_setting() {
  local key="$1"
  local fallback="$2"
  local jq
  if [[ ! -f "$CATWAY_SETTINGS_FILE" ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  jq="$(catway_jq)"
  "$jq" -r --arg key "$key" --argjson fallback "$fallback" \
    '.[$key] // $fallback' "$CATWAY_SETTINGS_FILE" 2>/dev/null || printf '%s\n' "$fallback"
}

catway_process_pid() {
  local pid command expected_executable
  [[ -r "$CATWAY_PID_FILE" ]] || return 1
  IFS= read -r pid < "$CATWAY_PID_FILE" || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  /bin/kill -0 "$pid" 2>/dev/null || return 1
  command="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
  expected_executable="$CATWAY_APP/Contents/MacOS/Catway"
  [[ "$command" == "$expected_executable" || "$command" == "$expected_executable "* ]] || return 1
  printf '%s\n' "$pid"
}

catway_trigger_sketchybar() {
  local sketchybar
  if sketchybar="$(catway_sketchybar 2>/dev/null)"; then
    "$sketchybar" --trigger catway_workspace_change >/dev/null 2>&1 || true
  fi
}

catway_ensure_config() {
  mkdir -p "$CATWAY_CONFIG_HOME" "$CATWAY_STATE_DIR"
  if [[ ! -f "$CATWAY_SETTINGS_FILE" ]]; then
    local template="$CATWAY_SHARE/integrations/settings.default.json"
    if [[ -r "$template" ]]; then
      install -m 0644 "$template" "$CATWAY_SETTINGS_FILE"
    else
      printf 'Catway: missing default settings template at %s\n' "$template" >&2
      return 1
    fi
  fi
}
