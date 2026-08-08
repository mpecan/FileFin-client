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

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is not on PATH.
       integration_test/support/fixture_run.dart repoints the copied cache at
       the copied media with it. Without that the cache still holds absolute
       paths into the shared seed, every suite reads the same bytes, and
       files[].path comes back ABSOLUTE where the contract says relative."

[ -d "$SUITE" ] || fail "$SUITE does not exist — there is no integration suite to run"

count=$(find "$SUITE" -name '*_test.dart' | grep -c . || true)
if [ "$count" -eq 0 ]; then
    fail "$SUITE has no *_test.dart files. A recipe over zero tests reports
       success, which is the one thing this gate may never do (§3)."
fi

# A suite that can excuse itself is the gate-that-cannot-fail in test clothes.
# `dart test` prints skipped tests in a colour nobody reads and still exits 0,
# so the only reliable answer is to refuse the marker outright. Written as
# character classes so these lines do not match themselves.
#
# The marker used to be `skip:` alone, which is ONE of the ways to skip and not
# the canonical one. Measured at M2: prepending `@Skip('temporarily disabled')`
# + `library;` to probe_and_login_test.dart turned 19 tests into 12, and this
# gate printed "All tests passed!" and exited 0 — the whole F1/F2 suite gone,
# with `dart format` and `dart analyze` both content. `solo:` and
# `markTestSkipped` evaded it too.
marker='@[S]kip|[s]kip[[:space:]]*:|[s]olo[[:space:]]*:|markTest[S]kipped'
if grep -rlE "$marker" "$SUITE" --include='*.dart' >/dev/null 2>&1; then
    grep -rnE "$marker" "$SUITE" --include='*.dart' | sed 's/^/  /'
    fail "the integration suite may not mark anything skippable.
       A suite that can skip itself reports success while checking nothing.
       If a case cannot run here, delete it and say so in STATE.md."
fi

# `dart_test.yaml` can exclude tests by tag, from a file this grep does not read
# and with no marker in any `*.dart` at all. There is no legitimate use for one
# here, so its mere existence is the failure.
if [ -e "$PKG/dart_test.yaml" ] || [ -e "$SUITE/dart_test.yaml" ]; then
    fail "a dart_test.yaml can exclude tests invisibly. Delete it."
fi

# --- reaping ----------------------------------------------------------------
#
# `addTearDown` does not run when the isolate is killed — a suite `@Timeout`,
# a Ctrl-C, a crashed VM — so servers and their 4 MB run directories accumulate.
# Observed after a week of M2: 5 orphaned `filefin serve` processes and 19
# leaked temp dirs (~80 MB).
#
# There is deliberately NO port-collision claim here, because there is no port
# collision: fixture_run.dart binds port 0 and the OS does not re-hand a port
# that is still LISTENing — `just it` was measured passing twice with five
# orphans alive. This reaps disk and processes, which is the real cost, and it
# runs BEFORE the suite so a failure leaves the evidence in place.
reap() {
    local dir pid reaped=0
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        rm -rf "$dir" && reaped=$((reaped + 1))
    done < <(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'filefin-it-*' -type d 2>/dev/null)
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
        reaped=$((reaped + 1))
    done < <(pgrep -f "$BIN serve" 2>/dev/null || true)
    [ "$reaped" -gt 0 ] && echo "it: reaped $reaped stale server(s)/directory(ies)"
    return 0
}
reap

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
#
# The output is CAPTURED and then asserted on, because the two things that make
# this gate real cannot be read from an exit code:
#
#   ~N   dart test exits 0 when tests are skipped. The grep above refuses the
#        skip syntaxes known TODAY; this refuses every one that exists, past or
#        future, including any invented after this line was written. It is the
#        load-bearing half — a grep can never anticipate the next syntax.
#   +N   the count. `count` above counts FILES, so a suite that stopped
#        declaring tests was tolerated as long as another file had some, and
#        `solo:` silently ran one test out of twenty while printing success.
#        FLOOR is a committed ratchet: raise it when tests are added, never
#        lower it to make a deletion pass.
FLOOR=26

echo "it: $count suite(s) against $BIN"
out=$(cd "$PKG" && dart test -j 1 --reporter expanded integration_test 2>&1) || {
    printf '%s\n' "$out"
    exit 1
}
printf '%s\n' "$out"

summary=$(printf '%s\n' "$out" | grep -E 'All tests passed!|Some tests failed' | tail -1)
[ -n "$summary" ] || fail "dart test printed no summary line — it did not run.
       Output above."

if printf '%s' "$summary" | grep -qE '~[0-9]+'; then
    fail "the suite reported SKIPPED tests: $summary
       A skipped integration test reports success while checking nothing.
       If a case cannot run here, delete it and say so in STATE.md."
fi

ran=$(printf '%s' "$summary" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+')
[ -n "$ran" ] || fail "could not read a test count from: $summary"
if [ "$ran" -lt "$FLOOR" ]; then
    fail "only $ran integration tests ran; the committed floor is $FLOOR.
       Tests do not disappear by accident. Raise FLOOR in this file when you
       add tests; lowering it to make a deletion pass is weakening the gate."
fi
echo "it: $ran tests, floor $FLOOR"
