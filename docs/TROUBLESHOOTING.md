# Troubleshooting

Start with:

```bash
catway doctor
```

## The wheel is slow the first time

Run `catway daemon`. A healthy installation prewarms the daemon from Hammerspoon and at the end of installation. `catway doctor` reports whether it is running.

## Four-finger swipe opens native Mission Control first

In Catway Settings, enable both **Four-finger wheel** and **Disable native Mission Control gesture**, then Apply. Confirm Hammerspoon has Accessibility permission. Log out and back in if macOS keeps an old trackpad preference cached.

## Shortcuts do not work

Confirm skhd is running and has Accessibility permission, then run:

```bash
skhd --reload
catway doctor
```

Catway loads `~/.config/catway/catway.skhdrc` from one marked block in the user's main `skhdrc`.

## The wheel lists empty workspaces

Enable **Show only active workspaces** in Settings. A focused empty Space may remain temporarily visible until focus changes so there is always a valid current workspace.

## Workspace indicators do not refresh

Run `catway bar-sync`. Catway uses `catway.space.*` item names to avoid deleting or changing unrelated SketchyBar items. Customize appearance in `~/.config/catway/sketchybar.local.sh`.

## Catway or Hammerspoon appears as the front app in SketchyBar

Front-app labels belong to the user's SketchyBar plugin. Add `Catway` and, if desired, `Hammerspoon` to that plugin's ignore list. Catway intentionally does not rewrite third-party front-app scripts.

## Reset only Catway integration files

Open Settings and click Apply. This regenerates Catway-owned files but does not touch the main user configs beyond their existing include blocks.

## Full removal

Run the uninstall command in the README. Do not manually delete `~/.config/catway/state` first; it contains the native Mission Control preference snapshot used for restoration.
