#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

ACTION="${1:-}"
[[ "$ACTION" == "install" || "$ACTION" == "uninstall" ]] || exit 64

HAMMERSPOON_CONFIG="${CATWAY_HAMMERSPOON_CONFIG:-$HOME/.hammerspoon/init.lua}"
SKHD_CONFIG="${CATWAY_SKHD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/skhd/skhdrc}"
YABAI_CONFIG="${CATWAY_YABAI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/yabai/yabairc}"
SKETCHYBAR_CONFIG="${CATWAY_SKETCHYBAR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar/sketchybarrc}"
BACKUP_DIR="$CATWAY_STATE_DIR/original-configs"

strip_marked_block() {
  local target="$1"
  local name="$2"
  local prefix="$3"
  local temporary start finish start_count finish_count start_line finish_line
  [[ -f "$target" ]] || return 0
  start="$prefix >>> Catway:$name >>>"
  finish="$prefix <<< Catway:$name <<<"
  start_count="$(grep -Fxc -- "$start" "$target" || true)"
  finish_count="$(grep -Fxc -- "$finish" "$target" || true)"
  if [[ "$start_count" == 0 && "$finish_count" == 0 ]]; then
    return 0
  fi
  if [[ "$start_count" != 1 || "$finish_count" != 1 ]]; then
    printf 'Catway: refusing to edit malformed %s block in %s\n' "$name" "$target" >&2
    return 65
  fi
  start_line="$(grep -nFx -- "$start" "$target" | cut -d: -f1)"
  finish_line="$(grep -nFx -- "$finish" "$target" | cut -d: -f1)"
  if (( start_line >= finish_line )); then
    printf 'Catway: refusing to edit out-of-order %s block in %s\n' "$name" "$target" >&2
    return 65
  fi
  temporary="$(mktemp "${target}.XXXXXX")"
  awk -v first="$start_line" -v last="$finish_line" 'NR < first || NR > last' "$target" > "$temporary"
  chmod --reference="$target" "$temporary" 2>/dev/null || chmod 0644 "$temporary"
  mv "$temporary" "$target"
}

strip_block() {
  local target="$1"
  local name="$2"
  local prefix='#'
  if [[ "$name" == "hammerspoon" ]]; then
    strip_marked_block "$target" "$name" '--'
    strip_marked_block "$target" "$name" '#'
  else
    strip_marked_block "$target" "$name" "$prefix"
  fi
}

backup_once() {
  local target="$1"
  local name="$2"
  mkdir -p "$BACKUP_DIR"
  if [[ ! -e "$BACKUP_DIR/$name" && ! -e "$BACKUP_DIR/$name.absent" ]]; then
    if [[ -f "$target" ]]; then
      cp -p "$target" "$BACKUP_DIR/$name"
    else
      : > "$BACKUP_DIR/$name.absent"
    fi
  fi
}

install_block() {
  local target="$1"
  local name="$2"
  local body="$3"
  local prefix='#'
  [[ "$name" == "hammerspoon" ]] && prefix='--'
  mkdir -p "$(dirname "$target")"
  [[ -e "$target" ]] || : > "$target"
  backup_once "$target" "$name"
  strip_block "$target" "$name"
  {
    printf '\n%s >>> Catway:%s >>>\n' "$prefix" "$name"
    printf '%b\n' "$body"
    printf '%s <<< Catway:%s <<<\n' "$prefix" "$name"
  } >> "$target"
}

if [[ "$ACTION" == "install" ]]; then
  catway_ensure_config
  install_block "$HAMMERSPOON_CONFIG" hammerspoon \
    "local catwayConfig = \"$CATWAY_CONFIG_HOME/hammerspoon.lua\"\nif hs.fs.attributes(catwayConfig) then dofile(catwayConfig) end"
  install_block "$SKHD_CONFIG" skhd \
    ".load \"$CATWAY_CONFIG_HOME/catway.skhdrc\""
  install_block "$YABAI_CONFIG" yabai \
    "[ -r \"$CATWAY_CONFIG_HOME/yabai.sh\" ] && . \"$CATWAY_CONFIG_HOME/yabai.sh\""
  install_block "$SKETCHYBAR_CONFIG" sketchybar \
    "[ -r \"$CATWAY_CONFIG_HOME/sketchybarrc\" ] && . \"$CATWAY_CONFIG_HOME/sketchybarrc\""
  printf 'Catway integration includes installed.\n'
else
  strip_block "$HAMMERSPOON_CONFIG" hammerspoon
  strip_block "$SKHD_CONFIG" skhd
  strip_block "$YABAI_CONFIG" yabai
  strip_block "$SKETCHYBAR_CONFIG" sketchybar
  printf 'Catway integration includes removed.\n'
fi
