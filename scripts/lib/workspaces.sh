#!/usr/bin/env bash

set -euo pipefail

catway_restore_labels() {
  local yabai jq registry spaces space_id label index
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  registry="$CATWAY_CONFIG_HOME/workspace-labels.tsv"
  [[ -f "$registry" ]] || return 0

  spaces="$($yabai -m query --spaces)"
  while IFS=$'\t' read -r space_id label; do
    [[ -n "$space_id" && -n "$label" ]] || continue
    index="$(printf '%s\n' "$spaces" | "$jq" -r --argjson id "$space_id" '.[] | select(.id == $id) | .index')"
    [[ "$index" =~ ^[0-9]+$ ]] || continue
    "$yabai" -m space "$index" --label "$label" >/dev/null 2>&1 || true
  done < "$registry"
  catway_trigger_sketchybar
}

catway_snapshot_labels() {
  local yabai jq registry temporary
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  registry="$CATWAY_CONFIG_HOME/workspace-labels.tsv"
  temporary="$(mktemp "${registry}.XXXXXX")"
  "$yabai" -m query --spaces | "$jq" -r '.[] | select(.label != "") | [.id, .label] | @tsv' > "$temporary"
  mv "$temporary" "$registry"
}

catway_record_label() {
  local space_id="$1"
  local label="$2"
  local registry temporary
  registry="$CATWAY_CONFIG_HOME/workspace-labels.tsv"
  temporary="$(mktemp "${registry}.XXXXXX")"
  if [[ -f "$registry" ]]; then
    awk -F'\t' -v id="$space_id" -v label="$label" '$1 != id && $2 != label' "$registry" > "$temporary"
  fi
  printf '%s\t%s\n' "$space_id" "$label" >> "$temporary"
  mv "$temporary" "$registry"
}

catway_internal_label() {
  local requested
  requested="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$requested" in
    [1-9]) printf 'N%s\n' "$requested" ;;
    [A-G]|I|[M-Z]) printf '%s\n' "$requested" ;;
    *) return 64 ;;
  esac
}

catway_resolve_label() {
  local label="$1"
  local yabai jq spaces target_index target_id current_label
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  spaces="$($yabai -m query --spaces)"
  target_index="$(printf '%s\n' "$spaces" | "$jq" -r --arg label "$label" '.[] | select(.label == $label) | .index')"

  if [[ -z "$target_index" ]]; then
    target_index="$(printf '%s\n' "$spaces" | "$jq" -r 'first(.[] | select((.windows | length) == 0) | .index) // empty')"
  fi
  if [[ -z "$target_index" ]]; then
    printf 'Catway: no empty native macOS Space is available for workspace %s.\n' "$label" >&2
    return 69
  fi

  current_label="$($yabai -m query --spaces --space "$target_index" | "$jq" -r '.label')"
  if [[ "$current_label" != "$label" ]]; then
    "$yabai" -m space "$target_index" --label "$label"
    target_id="$($yabai -m query --spaces --space "$target_index" | "$jq" -r '.id')"
    catway_record_label "$target_id" "$label"
    catway_trigger_sketchybar
  fi
  printf '%s\n' "$target_index"
}

catway_workspace_action() {
  local action="$1"
  local requested="$2"
  local label yabai jq window_id lock_dir acquired target_index focused_index
  [[ "$action" == "focus" || "$action" == "move" ]] || return 64
  label="$(catway_internal_label "$requested")" || return $?
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  window_id=""
  if [[ "$action" == "move" ]]; then
    window_id="$($yabai -m query --windows --window | "$jq" -r '.id')"
  fi

  lock_dir="$CATWAY_CONFIG_HOME/.workspace-lock"
  acquired=false
  for _ in {1..80}; do
    if mkdir "$lock_dir" 2>/dev/null; then
      acquired=true
      break
    fi
    sleep 0.025
  done
  [[ "$acquired" == true ]] || return 75
  trap 'rmdir "$lock_dir" 2>/dev/null || true' RETURN

  target_index="$(catway_resolve_label "$label")"
  if [[ "$action" == "move" ]]; then
    "$yabai" -m window "$window_id" --space "$target_index"
    catway_trigger_sketchybar
  else
    focused_index="$($yabai -m query --spaces --space | "$jq" -r '.index')"
    if [[ "$focused_index" != "$target_index" ]]; then
      "$yabai" -m space --focus "$target_index"
    fi
  fi
}

catway_focus_relative() {
  local direction="$1"
  local yabai jq spaces target
  [[ "$direction" == "next" || "$direction" == "previous" ]] || return 64
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  spaces="$($yabai -m query --spaces)"
  target="$(printf '%s\n' "$spaces" | "$jq" -r --arg direction "$direction" '
    [.[] | select(((.windows | length) > 0) or ."has-focus")] as $spaces
    | ($spaces | length) as $count
    | ($spaces | map(."has-focus") | index(true)) as $current
    | if $count < 2 or $current == null then empty
      elif $direction == "next" then $spaces[(($current + 1) % $count)].index
      else $spaces[(($current - 1 + $count) % $count)].index
      end
  ')"
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    "$yabai" -m space --focus "$target"
  fi
}

catway_focus_key() {
  local key yabai jq target
  key="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  [[ "$key" =~ ^[A-Z0-9]$ ]] || return 64
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  target="$($yabai -m query --spaces | "$jq" -r --arg key "$key" '
    def display_label:
      if (.label | test("^N[1-9]$")) then .label[1:]
      elif .label == "" then (.index | tostring)
      else .label
      end;
    first(.[] | select((.windows | length) > 0) | select((display_label | ascii_upcase) == $key) | .index) // empty
  ')"
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    catway_dismiss
    "$yabai" -m space --focus "$target"
    catway_trigger_sketchybar
  fi
}

catway_rotate_window() {
  local yabai jq count
  yabai="$(catway_yabai)"
  jq="$(catway_jq)"
  count="$($yabai -m query --windows --space | "$jq" '[.[] | select(."is-floating" == false and ."is-minimized" == false)] | length')"
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  (( count >= 2 )) || return 0

  if ! "$yabai" -m window --swap next >/dev/null 2>&1; then
    "$yabai" -m window --swap first
  fi
}
