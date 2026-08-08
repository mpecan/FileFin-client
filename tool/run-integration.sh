#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# `just it` — the integration suite, against a REAL filefin binary.
#
# CLAUDE.md: this "will fail when the binary is absent rather than skipping. A
# skipped integration suite that reports success is the gate-that-cannot-fail
# problem wearing a different hat." Every precondition below therefore FAILS.
# There is exactly one thing this script will fix for you — a missing seeded
# data directory — and that is because seeding is recoverable and deterministic
# while a missing binary is neither.
#
# It is NOT part of `just check`. CI has no filefin binary, so putting it there
# would make CI permanently red; `just check-all` is `check` plus this, and is
# local-only. STATE.md records that, and M2's definition of done is "`just
# check` exits 0 AND `just it` exits 0 on a machine with the binary".

PKG="packages/filefin_api"
SUITE="$PKG/integration_test"
BIN="${FILEFIN_BIN:-$HOME/development/filefin-test/filefin}"
RUN="${FILEFIN_RUN:-$HOME/development/filefin-test/run}"

# --- preconditions ----------------------------------------------------------

if [ ! -x "$BIN" ]; then
    fail "no executable filefin binary at $BIN.
       This suite exists to test against the real server; running it without
       one would report success over nothing. Build it:
         git clone https://github.com/xuedi/FileFin && cd FileFin \\
           && (cd web && npm install && npm run build) \\
           && GOTOOLCHAIN=auto go build -o filefin ./cmd/filefin
       Then point FILEFIN_BIN at it, or copy it to $BIN."
fi

command -v ffmpeg >/dev/null 2>&1 || fail "ffmpeg is not on PATH.
       tool/testserver/seed.sh encodes the H.264 and HEVC items that make both
       playback branches exist. Without it the library has no media and every
       browse assertion would be vacuous."

[ -d "$SUITE" ] || fail "$SUITE does not exist — there is no integration suite to run"

count=$(find "$SUITE" -name '*_test.dart' | grep -c . || true)
if [ "$count" -eq 0 ]; then
    fail "$SUITE has no *_test.dart files. A recipe over zero tests reports
       success, which is the one thing this gate may never do (§3)."
fi

# A suite that can excuse itself is the gate-that-cannot-fail in test clothes.
# `dart test` prints skipped tests in a colour nobody reads and still exits 0,
# so the only reliable answer is to refuse the marker outright. Written as a
# character class so this line does not match itself.
marker='[s]kip[:]'
if grep -rlE "$marker" "$SUITE" --include='*.dart' >/dev/null 2>&1; then
    grep -rnE "$marker" "$SUITE" --include='*.dart' | sed 's/^/  /'
    fail "the integration suite may not mark anything skippable.
       A suite that can skip itself reports success while checking nothing.
       If a case cannot run here, delete it and say so in STATE.md."
fi

# --- seeding ----------------------------------------------------------------
#
# The ONE recoverable precondition. Seeding is three ffmpeg encodes plus a cache
# rebuild, so it happens once and every suite copies the result
# (integration_test/support/fixture_run.dart explains why).
if [ ! -d "$RUN/data" ]; then
    echo "it: no seeded library at $RUN — seeding once"
    FILEFIN_BIN="$BIN" FILEFIN_RUN="$RUN" bash tool/testserver/seed.sh
fi

# --- run --------------------------------------------------------------------
#
# `-j 1` because each suite starts a real server. Concurrency here buys seconds
# and costs the ability to tell a port collision from a bug.
echo "it: $count suite(s) against $BIN"
(cd "$PKG" && dart test -j 1 --reporter expanded integration_test)
