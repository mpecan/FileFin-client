#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# First gate in `just check`. A missing or too-old SDK must fail loudly here,
# because every gate downstream of it would otherwise fail with a confusing
# message about something else — or, worse, "skip" and report success.
#
# 3.8 is the floor, and it is set by the STRICTEST constraint in the tree, not
# by the loosest. Pub workspaces need 3.6, but json_serializable 6.14 refuses to
# generate for a package whose language version is below 3.8 — it warns and
# emits older-shaped output rather than failing, which is the worst of both. The
# floor moves with whatever actually binds; grep the pubspecs for `sdk:` before
# changing it.

MIN_MAJOR=3
MIN_MINOR=8

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
