#!/usr/bin/env bash

set -euo pipefail

CATWAY_CONFIG_HOME="${CATWAY_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/catway}"
[[ -r "$CATWAY_CONFIG_HOME/sketchybar.local.sh" ]] && . "$CATWAY_CONFIG_HOME/sketchybar.local.sh"

YABAI="${CATWAY_YABAI:-$(command -v yabai 2>/dev/null || true)}"
JQ="${CATWAY_JQ:-$(command -v jq 2>/dev/null || true)}"
SKETCHYBAR="${CATWAY_SKETCHYBAR:-$(command -v sketchybar 2>/dev/null || true)}"
SPACE_SCRIPT="$CATWAY_CONFIG_HOME/sketchybar/space.sh"
[[ -x "$YABAI" && -x "$JQ" && -x "$SKETCHYBAR" ]] || exit 0

spaces="$($YABAI -m query --spaces 2>/dev/null)" || exit 0
known_items=""
while IFS=$'\t' read -r space_index space_label; do
  [[ -n "$space_index" ]] || continue
  item="catway.space.$space_index"
  known_items="$known_items $item"
  case "$space_label" in
    N[1-9]) display_label="${space_label#N}" ;;
    '') display_label="$space_index" ;;
    *) display_label="$space_label" ;;
  esac

  if ! "$SKETCHYBAR" --query "$item" >/dev/null 2>&1; then
    "$SKETCHYBAR" --add space "$item" left \
      --set "$item" \
        space="$space_index" \
        icon="$display_label" \
        label.drawing=off \
        icon.padding_left="${CATWAY_SPACE_PADDING_LEFT:-8}" \
        icon.padding_right="${CATWAY_SPACE_PADDING_RIGHT:-8}" \
        background.color="${CATWAY_SPACE_INACTIVE_BG:-0x40ffffff}" \
        background.corner_radius="${CATWAY_SPACE_CORNER_RADIUS:-5}" \
        background.height="${CATWAY_SPACE_HEIGHT:-25}" \
        background.drawing=on \
        click_script="\"$YABAI\" -m space --focus $space_index" \
        script="$SPACE_SCRIPT" \
      --subscribe "$item" space_change space_windows_change yabai_space_change catway_workspace_change
    if "$SKETCHYBAR" --query chevron >/dev/null 2>&1; then
      "$SKETCHYBAR" --move "$item" before chevron
    fi
  else
    "$SKETCHYBAR" --set "$item" \
      space="$space_index" \
      icon="$display_label" \
      click_script="\"$YABAI\" -m space --focus $space_index" \
      script="$SPACE_SCRIPT"
  fi
  NAME="$item" "$SPACE_SCRIPT"
done < <(printf '%s\n' "$spaces" | "$JQ" -r '.[] | select((.windows | length) > 0) | [.index, .label] | @tsv')

while IFS= read -r item; do
  [[ -n "$item" ]] || continue
  case " $known_items " in
    *" $item "*) ;;
    *) "$SKETCHYBAR" --remove "$item" ;;
  esac
done < <("$SKETCHYBAR" --query bar | "$JQ" -r '.items[] | select(startswith("catway.space."))')
