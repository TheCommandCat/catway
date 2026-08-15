# Architecture

Catway is split into three layers so that the interaction, window engine, and user configuration can evolve independently.

## Native app

`Sources/Catway` contains the Swift/AppKit app:

- `Models.swift` normalizes yabai's Space/window JSON and owns radial geometry.
- `YabaiClient.swift` locates yabai without assuming Intel or Apple Silicon Homebrew paths.
- `WheelView.swift` renders the cursor-centered SwiftUI wheel.
- `CatwayApp.swift` owns the prewarmed daemon, signal-based toggle/dismiss path, and Settings launch mode.
- `Settings.swift` persists product settings and applies them through the companion command.

The hidden daemon makes gesture-to-wheel latency independent of Swift process startup. `SIGUSR1` toggles and `SIGUSR2` dismisses. PID validation includes the executable command before sending a signal, preventing a stale PID file from targeting an unrelated process.

## Command layer

`scripts/catway` is the stable integration API. Workspace focus/move commands are serialized with a short directory lock. Native Space labels are stored against yabai Space IDs and restored after yabai reloads.

`rotate-windows` tries yabai's `next` window selector and wraps to `first`. This makes the action available from every tiled panel rather than only one side of the tree.

## Integrations

Catway never replaces a main dotfile. `manage-integrations.sh` adds one named block to each tool:

- Hammerspoon `dofile(...)`
- skhd `.load "..."`
- yabai shell source
- SketchyBar shell source

The operation is idempotent and the shell integration suite verifies that unrelated content survives install, reinstall, and uninstall.

## Engine boundary

The UI consumes normalized `WorkspaceModel` values. The first backend is `YabaiClient`. A future AeroSpace adapter should implement the same model and focus operations without introducing AeroSpace-specific details into the wheel.

## Security and privacy

Catway has no network client, telemetry, update checker, or credential storage. It executes locally installed window-management tools and reads only their workspace/window metadata. Hammerspoon and yabai Accessibility permissions remain visible, user-managed system permissions.
