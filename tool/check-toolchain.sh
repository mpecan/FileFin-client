#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# First gate in `just check`. A missing or too-old SDK must fail loudly here,
# because every gate downstream of it would otherwise fail with a confusing
# message about something else — or, worse, "skip" and report success.
#
# 3.6 is the floor: pub workspaces (`workspace:` in the root pubspec) need it,
# and so does the `resolution: workspace` line each member carries.

MIN_MAJOR=3
MIN_MINOR=6

command -v dart >/dev/null 2>&1 || fail "dart is not on PATH.
       Install the Flutter SDK and add its bin/ to PATH, e.g.
       export PATH=\"\$HOME/development/flutter/bin:\$PATH\""

version="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$version" ] || fail "could not parse a version out of 'dart --version'"

major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"

if [ "$major" -lt "$MIN_MAJOR" ] || { [ "$major" -eq "$MIN_MAJOR" ] && [ "$minor" -lt "$MIN_MINOR" ]; }; then
    fail "Dart $version is below the ${MIN_MAJOR}.${MIN_MINOR} floor this workspace needs"
fi

echo "toolchain: dart $version (floor ${MIN_MAJOR}.${MIN_MINOR})"
