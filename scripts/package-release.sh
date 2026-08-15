#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'Catway: invalid release version: %s\n' "$VERSION" >&2
  exit 64
fi
APP="$($ROOT/scripts/build-app.sh | tail -n 1)"
DESTINATION="$ROOT/build/Catway-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DESTINATION"
(cd "$(dirname "$DESTINATION")" && shasum -a 256 "$(basename "$DESTINATION")" > "$(basename "$DESTINATION").sha256")
printf '%s\n' "$DESTINATION"
