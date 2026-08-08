#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# The `just coverage-check` entry point: decides whether coverage is even
# measurable yet, then hands the actual thresholding to check-coverage.sh.
#
# The split is deliberate. check-coverage.sh reads an lcov file and nothing
# else, which is what lets it be proven against hand-made lcov files with known
# ratios. This wrapper owns the single "not yet" case, and that case is gated on
# there being no package at all — the first pubspec.yaml and the real gate runs.

if no_dart_packages; then
    echo "coverage-check: no Dart package in the tree yet — nothing to measure (M0 only)"
    exit 0
fi

# 50 is CLAUDE.md §3's tree-wide floor. The third argument is the one that
# protects a diff: an absolute ratchet on uncovered lines, which may only ever
# fall. See the header of check-coverage.sh for why the percentage alone cannot
# see an untested function.
exec bash tool/check-coverage.sh coverage/lcov.info 50 0
