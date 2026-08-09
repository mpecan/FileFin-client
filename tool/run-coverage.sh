#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Produce coverage/lcov.info from every pure-Dart package's test suite, for
# tool/check-coverage.sh to read.
#
# The empty-tree branch below is the one place this script can exit 0 without
# measuring anything, and it is gated on there being no package at all
# (`no_dart_packages`, tool/common.sh). The first pubspec.yaml makes it
# unreachable for good. STATE.md records it.

OUT="coverage"
LCOV="$OUT/lcov.info"
# The combined report is BUILT UNDER A DIFFERENT NAME and moved into place only
# once every check below has passed, and that is a foot-gun rather than a live
# hole. `just check` composes `coverage` and `coverage-gate` correctly, so the
# gate never saw a rejected report — but this script used to write
# `coverage/lcov.info` before the "every lib source produced a record" check,
# so a hand-run `bash tool/coverage-gate.sh` after a FAILED `just coverage`
# read the file that had just been rejected and reported "100% (2677/2677),
# exit 0" with an untested file sitting in the tree (M6.R/P3.8). A partial
# artefact with the final artefact's name is how a gate gets believed twice.
# `.partial` is deliberately not `*.lcov`, so the `cat` glob below cannot pick
# up its own output.
LCOV_STAGING="$OUT/lcov.info.partial"

if no_dart_packages; then
    echo "coverage: no Dart package in the tree yet — nothing to measure (M0 only)"
    exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT"

measured=0
while IFS= read -r pubspec; do
    pkg_dir="$(dirname "$pubspec")"
    # NOT `continue`. Skipping a package with no test/ dropped it out of the
    # denominator entirely, so `just coverage-check` on a tree where one package
    # was tested and another was not reported a clean 100%. A package with no
    # tests is the thing the floor exists to catch.
    [ -d "$pkg_dir/test" ] || \
        fail "$pkg_dir has no test/ directory. It would be dropped from the coverage
       denominator, which is not 0% — it is invisible. Write a test (§3), or
       delete the package (§1)."
    # In a pub WORKSPACE, `dart pub get` writes ONE package_config.json, at the
    # workspace root — members do not get their own. This line used to name
    # `$pkg_dir/.dart_tool/package_config.json` unconditionally, which was
    # correct for a standalone package and did not exist for the first member
    # that landed: format_coverage printed its usage and the run died on the
    # `cat` below. Prefer the package's own (a non-workspace package, or a
    # future one resolved standalone), fall back to the root's, and fail loudly
    # rather than passing an argument that silently means "no packages".
    echo "coverage: $pkg_dir"

    # The lcov file is named after the FULL path with slashes turned into
    # dashes, not after `basename "$pkg_dir"`. Under the basename the app's
    # file was literally `coverage/mobile.lcov`, so a future `packages/mobile`
    # would have overwritten it. That is fail-closed — the missing-record
    # cross-check below would then report every source of whichever package
    # lost the race — but it would name the wrong cause, and a gate that fails
    # for a reason its own message contradicts is a gate people learn to work
    # around.
    slug="${pkg_dir//\//-}"

    # THE FLUTTER BRANCH. `flutter test --coverage` writes lcov itself — there
    # is no `.vm.json` hitmap and no `format_coverage` step, so none of the
    # `--packages` / `--report-on` machinery below applies to it.
    #
    # What it writes is PACKAGE-RELATIVE: `SF:lib/src/app.dart`, from
    # `formatLcov(..., basePath: currentDirectory)` in the tool's
    # coverage_collector.dart. Measured at M3.0 on the pinned 3.44.9 before a
    # line of this was written, because the missing-record cross-check further
    # down anchors on the REPO-relative path and would have matched
    # `packages/filefin_core/lib/src/app.dart` just as happily.
    #
    # The shape is ASSERTED rather than assumed. If a future Flutter emitted
    # absolute paths, a blind `sed` would produce `SF:apps/mobile/lib//Users/…`
    # — a record matching no source, so every app source would read as missing
    # and the gate would fail loudly. That is the good case. The bad case is
    # the reverse: an `SF:` shape that happens to match after rewriting while
    # naming something else. So an `SF:` line that does not begin `SF:lib/` is
    # a hard failure here, where the message can say why.
    #
    # Also measured at M3.0: this path DOES honour `// coverage:ignore-file` —
    # a file carrying one disappears from the lcov entirely. The refusal of
    # that comment in hand-written lib source (below) therefore protects the
    # app exactly as it protects the packages, and `dart_lib_sources` already
    # covers `apps/*/lib`.
    if [ "${pkg_dir#apps/}" != "$pkg_dir" ]; then
        raw="$PWD/$OUT/$slug.flutter.lcov"
        # Same bounded, narrow retry the test gate uses: the libmpv crash costs
        # this run its whole lcov, and a coverage figure computed from a
        # half-written report would be wrong in the direction that fails
        # (tool/common.sh, M7.7). Measured 0 in 12 here against 2 in 42 for the
        # plain runner — rarer, same mechanism, same treatment.
        set +e
        run_tests_retrying_known_crash "$pkg_dir" \
            flutter test --coverage --coverage-path="$raw"
        cov_rc=$?
        set -e
        [ "$cov_rc" -eq 0 ] || fail "$pkg_dir: flutter test --coverage exited $cov_rc"
        [ -s "$raw" ] || fail "flutter test --coverage produced no lcov for $pkg_dir"
        bad=$(grep '^SF:' "$raw" | grep -cv '^SF:lib/' || true)
        if [ "$bad" -gt 0 ]; then
            grep '^SF:' "$raw" | grep -v '^SF:lib/' | sed 's/^/  /'
            fail "$bad SF: record(s) from 'flutter test --coverage' do not begin 'SF:lib/'.
       This script rewrites them to repo-relative paths so the missing-record
       cross-check below can match them. A different shape means that rewrite
       is now wrong, and a wrong rewrite is a record that silently names no
       file. Fix the rewrite; do not delete this check."
        fi
        sed "s|^SF:lib/|SF:$pkg_dir/lib/|" "$raw" > "$OUT/$slug.lcov"
        rm -f "$raw"
        measured=$((measured + 1))
        continue
    fi

    pkg_config="$pkg_dir/.dart_tool/package_config.json"
    [ -f "$pkg_config" ] || pkg_config=".dart_tool/package_config.json"
    [ -f "$pkg_config" ] || fail "no package_config.json for $pkg_dir — run 'dart pub get'"
    (cd "$pkg_dir" && dart test --coverage="../../$OUT/raw/$slug")
    # --check-ignore honours `// coverage:ignore-file`, which freezed writes on
    # line 2 of everything it generates. Without it the denominator is mostly
    # freezed's pattern-matching helpers (`when`, `maybeMap`, `whenOrNull`) —
    # code we never call and never will — and the figure reports 53% while every
    # line we wrote is covered. That is a broken instrument in the OTHER
    # direction from G2: the noise floor swamps a real regression.
    #
    # json_serializable does NOT write that comment, so the `.g.dart` decode
    # bodies stay in the denominator, which is right — they are the tolerant
    # decoding §8 is about. The hole this opens is closed immediately below.
    dart run coverage:format_coverage \
        --lcov \
        --check-ignore \
        --in="$OUT/raw/$slug" \
        --out="$OUT/$slug.lcov" \
        --packages="$pkg_config" \
        --report-on="$pkg_dir/lib"
    measured=$((measured + 1))
done < <(find packages apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null | sort)

if [ "$measured" -eq 0 ]; then
    fail "there are Dart sources but no package has a test/ directory — coverage would be vacuous"
fi

# `--check-ignore` above is only safe because of this. `// coverage:ignore-file`
# and `// coverage:ignore-line` delete lines from the denominator, so in
# hand-written source they are a one-comment opt-out of §3 — the exact shape of
# "do not weaken a gate to make it pass". Generated files may carry them
# (freezed writes one); ours may not, and `dart_lib_sources` already excludes
# *.g.dart and *.freezed.dart, so this loop sees only what we wrote.
ignoring=()
while IFS= read -r src; do
    [ -n "$src" ] || continue
    grep -qE '//[[:space:]]*coverage:ignore' "$src" && ignoring+=("$src")
done < <(dart_lib_sources)

if [ ${#ignoring[@]} -gt 0 ]; then
    printf '  %s\n' "${ignoring[@]}"
    fail "${#ignoring[@]} hand-written lib source(s) carry a 'coverage:ignore' comment.
       That deletes lines from the coverage denominator, which is an opt-out of
       the §3 floor written as a comment. Only generated files may carry it."
fi

cat "$OUT"/*.lcov > "$LCOV_STAGING"

# The floor's blind spot, and the reason it could not be breached by adding
# untested code.
#
# `dart test --coverage` collects from the VM service, which reports only the
# libraries the tests actually LOADED. `format_coverage --report-on=lib` filters
# that hitmap; it does not synthesise zero rows for a library nobody imported.
# So a lib/ file no test touches contributes no `DA:` records at all — it is not
# 0%, it is absent from the denominator. Measured: one tested one-line file plus
# an eleven-function file nobody imports reported "100% (1/1 lines)" and passed.
#
# Every non-generated lib source must therefore appear as an `SF:` record. A
# file that does not is not weakly tested, it is untested and unimported —
# unreachable from any test or running path, which §1 forbids and §3 measures.
# Failing here is louder and more honest than inventing a line count for it.
#
# THE ONE EXEMPTION, and it is mechanical rather than a list.
#
# A file with no executable code cannot produce a coverage record however well
# it is exercised: the VM emits a hitmap entry per compiled function, and a
# barrel of `export`s or a set of `extension type` declarations compiles to no
# functions at all. Measured on this tree: `lib/filefin_core.dart` (exports
# only) and `lib/src/ids.dart` (four empty-bodied extension types) are absent
# from the raw `.vm.json` hitmap entirely, even with a test that imports the
# barrel and constructs all four IDs. Requiring a record of them is requiring
# the impossible, and "delete them (§1)" is the wrong answer for a barrel.
#
# So a missing record is excused ONLY when the file is verified, line by line,
# to contain nothing but directives and empty-bodied extension types. There is
# no allowlist and no marker comment: both are things a reviewer can be talked
# past. To be exempt your file must literally have nowhere to put a statement,
# and the exempted files are printed on every run so the set stays visible.
# STATE.md records the decision.
#
# It COUNTS the offending lines rather than asking whether one exists, and that
# is not a style choice. The first version was
# `! sed … | grep -vE '^[[:space:]]*$' | grep -qvE '<allowed forms>'` under
# `set -euo pipefail`. `grep -q` exits the instant it matches, so on a file that
# DOES contain executable code the upstream `sed` and `grep -v` died of SIGPIPE
# (141); `pipefail` made 141 the pipeline's status and the leading `!` inverted
# it into "no executable code". The louder the evidence, the likelier the
# function said there was none — measured on a 2001-line file with
# `int sneak(int a, int b) => a > b ? a : b;` on line 1: 20 of 20 trials wrongly
# EXEMPT, and 9 of 20 at 53 KB, which is inside `file-size`'s 600-line hard
# limit. `grep -c` has to read every line to produce a count, so no reader can
# exit early, there is no pipe left to break, and the result is deterministic.
# `|| true` is required because `grep -c` exits 1 when the count is 0, which is
# the passing case here.
#
# The `library` alternative carries a word boundary (`library` alone, or
# `library` followed by whitespace). Without it `library[^;]*;` also excused
# `libraryHandle bar = compute();` — a real statement, exempted by a prefix.
has_no_executable_code() {
    local other
    other=$(
        sed -E 's|//.*$||' "$1" \
            | grep -cvE '^[[:space:]]*$|^[[:space:]]*(library([[:space:]][^;]*)?;|import[[:space:]][^;]*;|export[[:space:]][^;]*;|extension type const [A-Za-z_][A-Za-z0-9_]*\([A-Za-z_][A-Za-z0-9_<>?,[:space:]]*\) implements Object \{\})[[:space:]]*$'
    ) || true
    [ "${other:-1}" -eq 0 ]
}

missing=()
exempt=()
while IFS= read -r src; do
    [ -n "$src" ] || continue
    # SF: paths may be absolute or repo-relative depending on how the package
    # was resolved, so the match is anchored on the repo-relative suffix.
    if grep -qE "^SF:(.*/)?${src//./\\.}\$" "$LCOV_STAGING"; then
        continue
    fi
    if has_no_executable_code "$src"; then
        exempt+=("$src")
    else
        missing+=("$src")
    fi
done < <(dart_lib_sources)

if [ ${#missing[@]} -gt 0 ]; then
    printf '  %s\n' "${missing[@]}"
    fail "${#missing[@]} lib source(s) produced no coverage record at all.
       No test imports them, so they are missing from the denominator rather
       than sitting at 0% — the floor cannot see them. Import them from a test,
       or delete them (§1)."
fi

if [ ${#exempt[@]} -gt 0 ]; then
    echo "coverage: ${#exempt[@]} lib source(s) have no executable code and so no record:"
    printf '  %s\n' "${exempt[@]}"
fi

# Only now. Every refusal above leaves NO `coverage/lcov.info` at all, so a
# hand-run gate fails on a missing file instead of passing on a rejected one.
mv "$LCOV_STAGING" "$LCOV"

echo "coverage: wrote $LCOV from $measured package(s), covering every lib source"
