#!/usr/bin/env bash

set -euo pipefail

CATWAY_CONFIG_HOME="${CATWAY_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/catway}"
[[ -r "$CATWAY_CONFIG_HOME/sketchybar.local.sh" ]] && . "$CATWAY_CONFIG_HOME/sketchybar.local.sh"
YABAI="${CATWAY_YABAI:-$(command -v yabai 2>/dev/null || true)}"
JQ="${CATWAY_JQ:-$(command -v jq 2>/dev/null || true)}"
SKETCHYBAR="${CATWAY_SKETCHYBAR:-$(command -v sketchybar 2>/dev/null || true)}"
[[ -x "$YABAI" && -x "$JQ" && -x "$SKETCHYBAR" ]] || exit 0

space_index="${NAME#catway.space.}"
space_state="$($YABAI -m query --spaces --space "$space_index" 2>/dev/null | "$JQ" -r '[(.windows | length), ."has-focus"] | @tsv')"
if [[ -z "$space_state" ]]; then
  "$SKETCHYBAR" --set "$NAME" drawing=off
  exit 0
fi
IFS=$'\t' read -r window_count has_focus <<< "$space_state"
drawing=off
if (( window_count > 0 )) || [[ "${CATWAY_SHOW_EMPTY:-false}" == "true" ]]; then
  drawing=on
fi

if [[ "$has_focus" == "true" ]]; then
  "$SKETCHYBAR" --set "$NAME" drawing="$drawing" \
    icon.color="${CATWAY_SPACE_ACTIVE_FG:-0xff000000}" \
    background.color="${CATWAY_SPACE_ACTIVE_BG:-0xffffffff}"
else
  "$SKETCHYBAR" --set "$NAME" drawing="$drawing" \
    icon.color="${CATWAY_SPACE_INACTIVE_FG:-0xffffffff}" \
    background.color="${CATWAY_SPACE_INACTIVE_BG:-0x40ffffff}"
fi
