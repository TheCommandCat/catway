#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/mock-bin" "$TEST_ROOT/home" "$TEST_ROOT/runtime"

cat > "$TEST_ROOT/mock-bin/yabai" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  '-m query --spaces')
    printf '[{"id":1,"index":1,"label":"N1","windows":[42],"has-focus":true}]\n'
    ;;
  '-m query --spaces --space '*)
    printf '{"id":1,"index":1,"label":"N1","windows":[42],"has-focus":true}\n'
    ;;
  *) exit 0 ;;
esac
MOCK

cat > "$TEST_ROOT/mock-bin/defaults" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CATWAY_TEST_DEFAULTS_LOG:-/dev/null}"
if [[ "${1:-}" == read || ("${1:-}" == -currentHost && "${2:-}" == read) ]]; then
  exit 1
fi
exit 0
MOCK

for command in killall skhd; do
  cat > "$TEST_ROOT/mock-bin/$command" <<'MOCK'
#!/usr/bin/env bash
if [[ "$(basename "$0")" == skhd && "$*" == --reload && "${CATWAY_TEST_SKHD_PARSE_ERROR:-false}" == true ]]; then
  printf '#96:10 expected decl, modifier or key-literal\n' >> "$CATWAY_SKHD_ERROR_LOG"
fi
exit 0
MOCK
done

cat > "$TEST_ROOT/mock-bin/sketchybar" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == '--query bar' ]] && printf '{"items":[]}\n'
exit 0
MOCK

chmod +x "$TEST_ROOT/mock-bin/"*
export HOME="$TEST_ROOT/home"
export TMPDIR="$TEST_ROOT/runtime/"
export PATH="$TEST_ROOT/mock-bin:/opt/homebrew/bin:/usr/bin:/bin"
export CATWAY_PREFIX="$TEST_ROOT/prefix"
export CATWAY_CONFIG_HOME="$TEST_ROOT/config"
export CATWAY_TMPDIR="$TEST_ROOT/runtime"
export CATWAY_APP="$TEST_ROOT/home/Applications/Catway.app"
export CATWAY_YABAI="$TEST_ROOT/mock-bin/yabai"
export CATWAY_SKHD="$TEST_ROOT/mock-bin/skhd"
export CATWAY_SKETCHYBAR="$TEST_ROOT/mock-bin/sketchybar"
export CATWAY_TEST_DEFAULTS_LOG="$TEST_ROOT/defaults.log"
export CATWAY_SKHD_ERROR_LOG="$TEST_ROOT/skhd.err.log"

if CATWAY_APP=/ "$ROOT/scripts/install.sh" --no-open --no-start > "$TEST_ROOT/unsafe-install.log" 2>&1; then
  printf 'installer accepted a broad application path\n' >&2
  exit 1
fi
grep -q 'refusing broad application destination path' "$TEST_ROOT/unsafe-install.log"

"$ROOT/scripts/install.sh" --no-open --no-start
test -x "$CATWAY_PREFIX/bin/catway"
test -d "$CATWAY_APP"
test -f "$CATWAY_CONFIG_HOME/sketchybar/catway-process.png"
grep -q 'alt - 0x2C.*rotate-windows' "$CATWAY_CONFIG_HOME/catway.skhdrc"
grep -q '^alt - tab.*focus next' "$CATWAY_CONFIG_HOME/catway.skhdrc"
grep -q '^:: catway$' "$CATWAY_CONFIG_HOME/catway.skhdrc"
! grep -q 'catway-service' "$CATWAY_CONFIG_HOME/catway.skhdrc"
grep -q -- '-currentHost write NSGlobalDomain com.apple.trackpad.fourFingerVertSwipeGesture -int 0' "$CATWAY_TEST_DEFAULTS_LOG"
grep -q -- '-currentHost delete NSGlobalDomain com.apple.trackpad.fourFingerHorizSwipeGesture' "$CATWAY_TEST_DEFAULTS_LOG"

jq '.horizontalWorkspaceSwipe = true' "$CATWAY_CONFIG_HOME/settings.json" \
  > "$CATWAY_CONFIG_HOME/settings.json.updated"
mv "$CATWAY_CONFIG_HOME/settings.json.updated" "$CATWAY_CONFIG_HOME/settings.json"
"$CATWAY_PREFIX/bin/catway" sync-settings
grep -q 'write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 0' "$CATWAY_TEST_DEFAULTS_LOG"
grep -q 'write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 0' "$CATWAY_TEST_DEFAULTS_LOG"
grep -q -- '-currentHost write NSGlobalDomain com.apple.trackpad.fourFingerHorizSwipeGesture -int 0' "$CATWAY_TEST_DEFAULTS_LOG"
grep -q -- '-- >>> Catway:hammerspoon >>>' "$HOME/.hammerspoon/init.lua"
"$CATWAY_PREFIX/bin/catway" doctor
if CATWAY_TEST_SKHD_PARSE_ERROR=true "$CATWAY_PREFIX/bin/catway" doctor > "$TEST_ROOT/doctor-error.log" 2>&1; then
  printf 'doctor accepted an skhd parser failure\n' >&2
  exit 1
fi
grep -q 'parser rejected the loaded config' "$TEST_ROOT/doctor-error.log"

if CATWAY_APP=/ "$CATWAY_PREFIX/share/catway/scripts/uninstall.sh" > "$TEST_ROOT/unsafe-uninstall.log" 2>&1; then
  printf 'uninstaller accepted a broad application path\n' >&2
  exit 1
fi
grep -q 'refusing broad application destination path' "$TEST_ROOT/unsafe-uninstall.log"
test -d "$CATWAY_APP"

"$CATWAY_PREFIX/share/catway/scripts/uninstall.sh"
test ! -e "$CATWAY_APP"
test ! -e "$CATWAY_PREFIX/bin/catway"
! grep -Eq '^(#|--) >>> Catway:' "$HOME/.hammerspoon/init.lua"
printf 'Catway dry install/doctor/uninstall test passed.\n'
