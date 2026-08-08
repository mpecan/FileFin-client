#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ROOT="$(repo_root)"
cd "$ROOT"

# Capture test/fixtures/resume_vectors.json from the REAL upstream resume
# engine, by copying tool/fixtures/capture_state_vectors_test.go into a clone of
# FileFin at tag v0.20.3 and running it there (CLAUDE.md §8).
#
# This is M1.7's differential oracle: input→output pairs recorded from
# internal/state.Apply and .View themselves, rather than expectations we wrote
# from reading the code. A hand-written expectation can only encode what we
# already believe about the engine, which is exactly the thing under test.
#
# Requires network and Go. Upstream's go.mod asks for a newer toolchain than is
# usually installed, so GOTOOLCHAIN=auto is set to let Go fetch it. This script
# fails loudly rather than degrading: a fabricated vector file is worse than
# none, because M1 would then test the engine against our own guesses while
# reporting that it had an oracle.

TAG="v0.20.3"
COMMIT="9399feb8f2f20cfad9f8d5be070d723faff5b3f6"
OUT="$ROOT/test/fixtures/resume_vectors.json"
SRC="$ROOT/tool/fixtures/capture_state_vectors_test.go"
CLONE="${FILEFIN_UPSTREAM_CLONE:-}"

command -v go >/dev/null 2>&1 || fail "go is not on PATH — cannot run the upstream engine"
[ -f "$SRC" ] || fail "$SRC is missing"

work=""
cleanup() { [ -n "$work" ] && rm -rf "$work"; }
trap cleanup EXIT

if [ -n "$CLONE" ]; then
    [ -d "$CLONE/internal/state" ] || fail "FILEFIN_UPSTREAM_CLONE=$CLONE has no internal/state"
    have="$(cd "$CLONE" && git rev-parse HEAD)"
    [ "$have" = "$COMMIT" ] || fail "FILEFIN_UPSTREAM_CLONE is at $have, not $COMMIT ($TAG).
       The vectors must come from the version docs/server-api.md is pinned to."
    work="$(mktemp -d)"
    cp -R "$CLONE/" "$work/upstream"
    repo="$work/upstream"
else
    work="$(mktemp -d)"
    repo="$work/upstream"
    echo "cloning FileFin $TAG (needs network)..."
    git clone --quiet --depth 1 --branch "$TAG" https://github.com/xuedi/FileFin "$repo" || \
        fail "could not clone FileFin $TAG. Point FILEFIN_UPSTREAM_CLONE at an
       existing clone checked out at $COMMIT, or restore network access."
    have="$(cd "$repo" && git rev-parse HEAD)"
    [ "$have" = "$COMMIT" ] || fail "$TAG resolved to $have, not the expected $COMMIT"
fi

cp "$SRC" "$repo/internal/state/capture_state_vectors_test.go"

echo "running the upstream engine..."
(
    cd "$repo"
    GOTOOLCHAIN=auto GOFLAGS=-mod=mod \
        FILEFIN_VECTORS_OUT="$OUT" \
        go test ./internal/state/ -run TestCaptureStateVectors -v
) || fail "the capture test did not run.
       If the failure mentions a toolchain download, Go needs network to fetch
       the version upstream's go.mod requires (GOTOOLCHAIN=auto is already set).
       Do NOT hand-write test/fixtures/resume_vectors.json instead — a
       fabricated oracle is worse than no oracle."

[ -s "$OUT" ] || fail "the test reported success but wrote nothing to $OUT"

count=$(grep -c '"name":' "$OUT" || true)
[ "$count" -gt 100 ] || fail "only $count vectors captured — the grid did not run"

echo "resume vectors: $count captured into $OUT from $TAG ($COMMIT)"
echo "Refresh the fixture manifest: bash tool/check-fixtures.sh accept"
