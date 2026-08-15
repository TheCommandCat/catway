# Contributing

Catway welcomes focused bug reports and small, testable pull requests.

Before opening a change:

```bash
swift test
./Tests/shell/integration.sh
./Tests/shell/install.sh
./Tests/shell/release.sh
find scripts integrations Tests -type f \( -name '*.sh' -o -name 'catway' \) -print0 | xargs -0 -n1 bash -n
./scripts/build-app.sh
codesign --verify --deep --strict build/Catway.app
```

Keep user ownership as a hard constraint: do not replace an entire Hammerspoon, skhd, yabai, or SketchyBar config. New integration behavior must be removable and idempotent.

Bug reports should include macOS version, yabai version, `catway doctor` output, display count, and whether the issue occurs with keyboard, gesture, or both. Remove private app/window names if needed.
