#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
PID_PROBE_PID=""
cleanup() {
  if [[ "$PID_PROBE_PID" =~ ^[0-9]+$ ]]; then
    kill "$PID_PROBE_PID" >/dev/null 2>&1 || true
    wait "$PID_PROBE_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
MOCK_BIN="$TEST_ROOT/bin"
CONFIG="$TEST_ROOT/config"
LOG="$TEST_ROOT/yabai.log"
mkdir -p "$MOCK_BIN" "$CONFIG"

cat > "$MOCK_BIN/yabai" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CATWAY_TEST_LOG"
case "$*" in
  '-m query --windows --space')
    printf '[{"is-floating":false,"is-minimized":false},{"is-floating":false,"is-minimized":false}]\n'
    ;;
  '-m window --swap next')
    exit "${CATWAY_TEST_NEXT_STATUS:-0}"
    ;;
  '-m query --spaces')
    printf '[{"index":1,"label":"N1","windows":[1],"has-focus":true}]\n'
    ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK_BIN/yabai"

export CATWAY_SHARE="$ROOT"
export CATWAY_CONFIG_HOME="$CONFIG"
export CATWAY_YABAI="$MOCK_BIN/yabai"
export CATWAY_JQ="$(command -v jq)"
export CATWAY_TEST_LOG="$LOG"

PID_PROBE_ROOT="$TEST_ROOT/pid-probe"
PID_PROBE_APP="$PID_PROBE_ROOT/Catway.app"
mkdir -p "$PID_PROBE_APP/Contents/MacOS" "$PID_PROBE_ROOT/runtime"
xcrun clang -x c -o "$PID_PROBE_APP/Contents/MacOS/Catway" - <<'PROBE'
#include <unistd.h>
int main(void) {
  sleep(30);
  return 0;
}
PROBE
"$PID_PROBE_APP/Contents/MacOS/Catway" 30 &
PID_PROBE_PID=$!
printf '%s\n' "$PID_PROBE_PID" > "$PID_PROBE_ROOT/runtime/catway.pid"
(
  export CATWAY_APP="$PID_PROBE_APP"
  export CATWAY_TMPDIR="$PID_PROBE_ROOT/runtime"
  # shellcheck source=../../scripts/lib/common.sh
  . "$ROOT/scripts/lib/common.sh"
  [[ "$(catway_process_pid)" == "$PID_PROBE_PID" ]]
)
if (
  export CATWAY_APP="$TEST_ROOT/different/Catway.app"
  export CATWAY_TMPDIR="$PID_PROBE_ROOT/runtime"
  # shellcheck source=../../scripts/lib/common.sh
  . "$ROOT/scripts/lib/common.sh"
  catway_process_pid >/dev/null
); then
  printf 'PID validation accepted a different Catway executable\n' >&2
  exit 1
fi
kill "$PID_PROBE_PID"
wait "$PID_PROBE_PID" >/dev/null 2>&1 || true
PID_PROBE_PID=""

grep -Fq 'local physicalBacktickKeyCode = 50' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'hs.eventtap.keyStrokes("`")' "$ROOT/integrations/hammerspoon/catway.lua.template"
! grep -Fq 'hs.keycodes.map["`"]' "$ROOT/integrations/hammerspoon/catway.lua.template"
! grep -Fq 'hs.eventtap.keyStroke({}, "`"' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'if dy > 0 and not wheelVisible then' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'elseif dy < 0 and wheelVisible then' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'run({ "dismiss" })' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'gestureState.axis = "vertical"' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'gestureState.axis = "horizontal"' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq 'return gestureState.axis == "vertical"' "$ROOT/integrations/hammerspoon/catway.lua.template"
grep -Fq '.moveToActiveSpace' "$ROOT/Sources/Catway/CatwayApp.swift"
! grep -Fq '.canJoinAllSpaces' "$ROOT/Sources/Catway/CatwayApp.swift"

CATWAY_TEST_NEXT_STATUS=1 "$ROOT/scripts/catway" rotate-windows
grep -q -- '-m window --swap next' "$LOG"
grep -q -- '-m window --swap first' "$LOG"

: > "$LOG"
CATWAY_TEST_NEXT_STATUS=0 "$ROOT/scripts/catway" rotate-windows
grep -q -- '-m window --swap next' "$LOG"
if grep -q -- '-m window --swap first' "$LOG"; then
  printf 'rotate-windows wrapped even though next succeeded\n' >&2
  exit 1
fi

HAMMERSPOON="$TEST_ROOT/hammerspoon.lua"
SKHD="$TEST_ROOT/skhdrc"
YABAIRC="$TEST_ROOT/yabairc"
SKETCHYBARRC="$TEST_ROOT/sketchybarrc"
printf 'user_hammerspoon = true\n' > "$HAMMERSPOON"
printf '# user skhd\n' > "$SKHD"
printf '# user yabai\n' > "$YABAIRC"
printf '# user sketchybar\n' > "$SKETCHYBARRC"
export CATWAY_HAMMERSPOON_CONFIG="$HAMMERSPOON"
export CATWAY_SKHD_CONFIG="$SKHD"
export CATWAY_YABAI_CONFIG="$YABAIRC"
export CATWAY_SKETCHYBAR_CONFIG="$SKETCHYBARRC"

"$ROOT/scripts/manage-integrations.sh" install >/dev/null
"$ROOT/scripts/manage-integrations.sh" install >/dev/null
for spec in \
  "$HAMMERSPOON:hammerspoon" \
  "$SKHD:skhd" \
  "$YABAIRC:yabai" \
  "$SKETCHYBARRC:sketchybar"
do
  file="${spec%:*}"
  name="${spec##*:}"
  [[ "$(grep -Ec "^(#|--) >>> Catway:$name >>>" "$file")" == 1 ]]
done
grep -q 'user_hammerspoon = true' "$HAMMERSPOON"

"$ROOT/scripts/manage-integrations.sh" uninstall >/dev/null
! grep -Eq '^(#|--) >>> Catway:' "$HAMMERSPOON"
! grep -q '# >>> Catway:' "$SKHD"
! grep -q '# >>> Catway:' "$YABAIRC"
! grep -q '# >>> Catway:' "$SKETCHYBARRC"
grep -q 'user_hammerspoon = true' "$HAMMERSPOON"

printf 'user_hammerspoon = true\n-- >>> Catway:hammerspoon >>>\nprotected_tail = true\n' > "$HAMMERSPOON"
malformed_before="$(shasum -a 256 "$HAMMERSPOON")"
if "$ROOT/scripts/manage-integrations.sh" uninstall >/dev/null 2>&1; then
  printf 'malformed integration block was accepted\n' >&2
  exit 1
fi
[[ "$(shasum -a 256 "$HAMMERSPOON")" == "$malformed_before" ]]
grep -q 'protected_tail = true' "$HAMMERSPOON"

printf 'Catway shell integration tests passed.\n'
