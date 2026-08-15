# Changelog

## 0.1.1 - 2026-08-15

- Make the PID ownership probe portable across GitHub-hosted macOS runners.
- Update GitHub Actions to the current Node 24-based checkout release.
- Add a centered, search-friendly project title and description to the README.

## 0.1.0 - 2026-08-15

- Native cursor-centered radial workspace overview.
- Active-workspace filtering with app icons and direct label selection.
- Prewarmed daemon and signal-based instant toggle/dismiss path.
- Directional four-finger vertical gesture bridge plus native horizontal Space animation by default.
- Optional active-workspace-only horizontal cycling for users who prefer it over the native animation.
- Double-backtick toggle and bare workspace keys while open.
- Dynamic native workspace labels, move/focus shortcuts, and active-workspace cycling.
- `Option+/` window-position cycling from every tiled panel.
- Optional user-owned skhd, yabai, Hammerspoon, and SketchyBar integrations.
- Native Settings window, doctor, installer, uninstaller, preference restoration, tests, and CI.
- Isolated runtime/PID ownership checks prevent test or stale state from targeting another Catway process.
