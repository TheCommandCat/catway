#!/usr/bin/env bash

set -euo pipefail

JQ="${CATWAY_JQ:-$(command -v jq 2>/dev/null || true)}"
SKETCHYBAR="${CATWAY_SKETCHYBAR:-$(command -v sketchybar 2>/dev/null || true)}"
[[ -x "$JQ" && -x "$SKETCHYBAR" ]] || exit 0

while IFS= read -r item; do
  [[ -n "$item" ]] && "$SKETCHYBAR" --remove "$item"
done < <("$SKETCHYBAR" --query bar | "$JQ" -r '.items[] | select(startswith("catway.space."))')
