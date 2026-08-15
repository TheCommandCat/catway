#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="0.1.1-test"
if "$ROOT/scripts/package-release.sh" '../outside' >/dev/null 2>&1; then
  printf 'release packager accepted an unsafe version\n' >&2
  exit 1
fi
ARCHIVE="$($ROOT/scripts/package-release.sh "$VERSION" | tail -n 1)"
CHECKSUM="$ARCHIVE.sha256"
ARCHIVE_NAME="$(basename "$ARCHIVE")"

[[ -f "$ARCHIVE" && -f "$CHECKSUM" ]]
grep -Eq "^[0-9a-f]{64}  ${ARCHIVE_NAME}$" "$CHECKSUM"
! grep -Fq "$ROOT" "$CHECKSUM"
(cd "$(dirname "$ARCHIVE")" && shasum -a 256 -c "$(basename "$CHECKSUM")")

contents="$(unzip -Z1 "$ARCHIVE")"
printf '%s\n' "$contents" | grep -q '^Catway.app/Contents/MacOS/Catway$'
if printf '%s\n' "$contents" | grep -q '/assets/concepts/'; then
  printf 'release archive contains development concept assets\n' >&2
  exit 1
fi

printf 'Catway release archive test passed.\n'
