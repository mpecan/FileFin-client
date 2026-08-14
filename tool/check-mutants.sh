#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ROOT="$(repo_root)"
cd "$ROOT"

# Mutation gate (CLAUDE.md §3).
#
# Scoped to the diff against FILEFIN_MUTANTS_BASE (default HEAD), and to `lib/`
# only. A whole-tree run mutates every line of every model on every commit; the
# diff of one commit is the code this commit is actually responsible for.
#
# `mutation_test` REWRITES SOURCE FILES IN PLACE and restores them afterwards.
# **Since M8.R those files live in a disposable worktree, not in yours** — see
# the block above the package loop for why a clean-tree precondition was the
# wrong fix and what `git stash create` buys instead.
#
# That removes the reason this gate had to be last in `just check` and had to
# not overlap another gate: it no longer edits the files the other gates read.
# It is still listed last, because a gate measured in minutes belongs after the
# ones measured in seconds, and because being wrong about this once cost four
# mutants left on disk.
#
# Exit statuses of the tool itself, verified against the pinned 1.7.1:
#   0    every mutant killed
#   255  the threshold was missed — at least one mutant survived

RULES="$ROOT/mutation_rules.xml"
BASE="${FILEFIN_MUTANTS_BASE:-HEAD}"

command -v dart >/dev/null 2>&1 || fail "dart not on PATH"
[ -f "$RULES" ] || fail "$RULES is missing — the gate has no threshold and no exclusions without it"

git rev-parse --verify --quiet "$BASE" >/dev/null || fail "FILEFIN_MUTANTS_BASE=$BASE is not a valid revision"

# THE TEST COMMAND IS PER PACKAGE, AND IT LIVES IN THE GENERATED TARGETS FILE
# BELOW — NOT IN mutation_rules.xml. This refusal is what keeps it that way.
#
# Measured at M3.0 against the pinned mutation_test 1.7.1: a `<commands>` block
# in the rules document runs IN ADDITION to a `<commands>` block in the targets
# document. It is not an overridable default. With `dart test` in the rules and
# `flutter test` in the targets, `dart test` still ran inside `apps/mobile` and
# still failed — measured, not reasoned.
#
# What that failure looks like is worth recording, because it is milder than
# expected and the expectation is what this comment is for. mutation_test runs
# the command set against UNMODIFIED code first, so a command that always fails
# aborts the run ("Running the test commands failed with unmodified code!
# Aborting.", rc 1) rather than marking every mutant detected. Both halves of
# this script then refuse it: rc != 0 sets `status`, and no "Found N mutations"
# line means `found` is 0, which is its own hard failure. So the old wiring was
# fail-CLOSED, not the silent 100%-over-nothing this comment was drafted to
# warn about. It still cannot run the app's suite at all, which is reason
# enough — and the next global command someone adds may not fail so honestly.
#
# The check reads XML, not text. `grep -q` over the raw file was the first
# version and it failed on a CORRECT rules file: the comment explaining why
# there is no commands block contains the element name, so the gate refused the
# very state it exists to enforce. That is CLAUDE.md's "an assertion satisfiable
# in prose" with the sign flipped — a rule a comment can break is as broken as
# one a comment can satisfy. mutation_test does not read comments, so neither
# does this: `<!-- … -->` spans are stripped first, across lines.
strip_xml_comments() {
    awk '
        {
            res = ""; line = $0
            while (line != "") {
                if (incomment) {
                    i = index(line, "-->")
                    if (i == 0) { line = "" } else { line = substr(line, i + 3); incomment = 0 }
                } else {
                    i = index(line, "<!--")
                    if (i == 0) { res = res line; line = "" }
                    else { res = res substr(line, 1, i - 1); line = substr(line, i + 4); incomment = 1 }
                }
            }
            print res
        }
    ' "$1"
}

# `<commands[[:space:]]*>` rather than the literal, because XML permits
# whitespace before the closing angle bracket and mutation_test's parser
# accepts it: a reproduction ran with `<commands  >`, executed `dart test` out
# of the rules file exactly as the refusal below describes, and the refusal
# never fired. A gate a single space turns off is a gate you have already lost.
if strip_xml_comments "$RULES" | grep -qE '<commands[[:space:]]*>'; then
    fail "$RULES declares a <commands> block.
       It would run IN ADDITION to the per-package command this script writes
       into its generated targets file, so every package would also be tested
       with the wrong runner. Measured at M3.0 on mutation_test 1.7.1. The
       test command belongs in the targets document, which knows which package
       it is building. Delete the block from the rules file."
fi

# The gate's one structural blind spot, and it sat over the place it mattered
# most. The default BASE is `HEAD`, which is right locally — the working tree vs
# the last commit is what the commit about to be made is responsible for. But CI
# checks out a commit, so the working tree IS HEAD: `git diff HEAD` is empty,
# `changed` is empty, and the script below reported "nothing to mutate" and
# exited 0 on every PR and every push. §3's whole answer to "coverage cannot
# tell a real assertion from a tautology" was dead wherever it was not being
# watched.
#
# Under $CI that combination is now a hard failure rather than a silent pass.
# .github/workflows/ci.yml passes the PR base sha (or HEAD^) — the workflow
# already sets fetch-depth: 0 so both resolve.
if [ -n "${CI:-}" ] \
    && [ "$(git rev-parse "$BASE")" = "$(git rev-parse HEAD)" ] \
    && [ -z "$(git status --porcelain)" ]; then
    fail "FILEFIN_MUTANTS_BASE resolves to HEAD and the tree is clean, so this
       gate would diff a commit against itself and mutate nothing. Under \$CI
       that is a configuration error, not a clean run. Pass a real base:
       the pull request's base sha, or HEAD^ on a push."
fi

# Tracked changes plus untracked files. `git diff` does not see a brand-new
# file, and a brand-new file is precisely the code that has never been tested —
# omitting it is how this gate would report success over unexercised code.
changed=$(
    {
        git diff --name-only "$BASE" -- '*.dart'
        git ls-files --others --exclude-standard -- '*.dart'
    } | sort -u | while IFS= read -r f; do
        case "$f" in
            */lib/*.dart) ;;
            *) continue ;;
        esac
        case "$f" in
            *.g.dart|*.freezed.dart) continue ;;
        esac
        [ -f "$f" ] || continue
        echo "$f"
    done
)

if [ -z "$changed" ]; then
    # Legitimate, not a skip: a docs-only or gate-only commit changes no Dart
    # library source, so there is nothing whose behaviour a mutant could alter.
    # The message names the base so a surprising "nothing to do" is debuggable
    # rather than trusted.
    echo "mutants: no changed Dart lib sources vs $BASE — nothing to mutate"
    exit 0
fi

# A COMMENT-ONLY DIFF HAS NOTHING TO MUTATE, and skipping it is a correctness
# statement rather than a shortcut.
#
# `mutation_test` rewrites operators, literals and conditions. It never touches
# a comment, so the mutants generated for a file whose code is byte-identical to
# the base are exactly the mutants the base would have generated — the run
# re-verifies the existing suite against existing code and says nothing about
# the diff. That is a whole-tree mutation baseline, which is a worthwhile thing
# to run deliberately and a wasteful thing to run per commit.
#
# The cost of not having this was measured at M8.R: a documentation pass that
# changed 81 lib files and ZERO lines of code faced a ~10-hour serial sweep,
# and `mutants-parallel` could not take it either (it shards one package; that
# diff spanned three). A gate that expensive on a change that cannot fail it is
# a gate people learn to skip.
#
# The decision lives in `file_is_comment_only` in common.sh, which states how it
# fails closed and which shapes it refuses to analyse. It is there rather than
# here so it can be proven WITHOUT starting a mutation run — killing a live
# `mutation_test` to test this is what leaves a mutant on disk, and doing
# exactly that is how a proof attempt corrupted `app.dart` mid-write.
#
# FILTERED PER FILE, NOT ALL OR NOTHING, and the difference is not academic: the
# first version asked the question of the whole diff, so this same pass — a
# documentation sweep that also corrected two user-facing strings — put 59 files
# in front of `mutation_test` in order to learn something about two, with a
# 68-hour whole-run cap. Dropping the comment-only files leaves exactly the ones
# whose behaviour could have changed.
total=$(printf '%s\n' "$changed" | wc -l | tr -d ' ')
changed=$(
    printf '%s\n' "$changed" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        file_is_comment_only "$BASE" "$f" || echo "$f"
    done
)
skipped=$(( total - $(printf '%s\n' "$changed" | grep -c . || true) ))
[ "$skipped" -gt 0 ] &&
    echo "mutants: $skipped changed lib file(s) differ from $BASE only in comments —
         code byte-identical, so their mutants would be the base's own. Dropped."

if [ -z "$changed" ]; then
    echo "mutants: nothing left to mutate; every changed lib source was comments."
    echo "         (Run a whole-tree baseline deliberately, not from here.)"
    exit 0
fi

# THE MUTATIONS HAPPEN IN A DISPOSABLE WORKTREE, NEVER IN THE TREE YOU ARE
# STANDING IN. This is the single most important line in the file.
#
# `mutation_test` rewrites a source, runs the suite, and restores it. Interrupt
# it — a timeout, a Ctrl-C, a SIGTERM, a laptop lid — and the mutant it was
# holding stays on disk. That happened FOUR times during M8.R alone, and one of
# them was `500 * 1000 * -1000`, which `dart analyze` reports as "No issues
# found" because a negated literal is perfectly good Dart.
#
# The reason it was never simply cleaned up is the one that matters: **on a
# dirty tree there is no safe automatic recovery.** A `git checkout --` cannot
# tell the mutant from the uncommitted edit the run exists to test, so the only
# available repair destroys the work. That is why this script had no `trap`
# while run-mutants-parallel.sh has had one all along — the parallel driver owns
# disposable worktrees and can clean up unconditionally. Now so can this.
#
# A CLEAN-TREE PRECONDITION WOULD HAVE BEEN THE WRONG FIX, and it is worth
# saying why so nobody proposes it again. The gate is diff-scoped against
# `HEAD` by default, so on a clean tree `git diff HEAD` is empty and it reports
# "nothing to mutate". Requiring a clean tree would mean it measures nothing
# locally and runs only in CI — which is exactly the silent no-op the `$CI`
# guard above exists to catch.
#
# `git stash create` is what makes this possible: it writes a commit object for
# the current working tree WITHOUT touching the stash stack, the index or the
# tree. Untracked files are not in that commit, so they are copied in — and they
# matter, because a brand-new file is precisely the code that has never been
# tested and `changed` deliberately includes it.
#
# Measured cost, apps/mobile: 1s to add the worktree, 1s for `pub get`, 5s for
# the first suite against a cold `.dart_tool` — 7s against a run measured in
# minutes to hours. Measured rather than assumed, because the RAM-disk
# experiment (STATE.md, M8) is the standing reminder that intuitions about this
# particular cache are unreliable.
WT="${TMPDIR:-/tmp}/filefin-mutants-wt.$$"
cleanup_worktree() {
    [ -n "${WT:-}" ] || return 0
    git worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
    git worktree prune >/dev/null 2>&1 || true
}
trap cleanup_worktree EXIT INT TERM

snapshot="$(git stash create 2>/dev/null || true)"
git worktree add --detach "$WT" "${snapshot:-HEAD}" >/dev/null 2>&1 \
    || fail "could not create the mutation worktree at $WT"
git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
    mkdir -p "$WT/$(dirname "$f")" && cp "$f" "$WT/$f"
done
echo "mutants: mutating a disposable worktree; your working tree is not touched"

# Group by owning package: mutation_test runs the test command from a working
# directory, and `dart test` only means anything inside a package.
packages=$(printf '%s\n' "$changed" | sed 's|/lib/.*||' | sort -u)

status=0
for pkg in $packages; do
    [ -f "$pkg/pubspec.yaml" ] || fail "$pkg has changed lib sources but no pubspec.yaml"
    [ -d "$pkg/test" ] || fail "$pkg has changed lib sources but no test/ directory — a mutation run with no tests kills nothing"

    # A temp DIRECTORY with fixed filenames inside, not `mktemp` templates with
    # a suffix. BSD/macOS mktemp only substitutes the `X`s when they end the
    # template: given `filefin-mutants-XXXXXX.xml` it creates a file called
    # exactly that, literally, and the NEXT run gets
    # `mkstemp failed … File exists` and the gate cannot run at all.
    #
    # Normally the `rm -f` at the end of the loop hides it. An interrupted run
    # does not reach that line, and from then on the gate is dead until someone
    # deletes a file with six literal X's in its name — which is not a message
    # anybody decodes quickly. Measured on macOS: the second `mktemp` with this
    # template returns the literal path and rc 0, the third fails with rc 1.
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/filefin-mutants-XXXXXX")"
    targets="$tmpdir/targets.xml"

    # The runner, by LOCATION, for the same reason tool/run-tests.sh chooses it
    # that way: `packages/*` is pure Dart, `apps/*` is Flutter. run-tests.sh is
    # what cross-checks that against the pubspec and fails on a disagreement,
    # so this is one rule enforced in one place and consulted in two.
    #
    # `--no-pub` here and NOT in run-tests.sh, deliberately. This gate runs the
    # suite once per mutant — tens to hundreds of times — and an implicit `pub
    # get` on each one costs more than the mutation. run-tests.sh keeps the
    # implicit resolve so a stale or broken resolution fails there, loudly,
    # once, instead of being papered over everywhere.
    case "$pkg" in
        apps/*)     test_cmd='flutter test --no-pub' ;;
        packages/*) test_cmd='dart test' ;;
        *) fail "$pkg is neither under packages/ nor apps/, so there is no rule
       for which test runner mutation_test should use. Add one here." ;;
    esac

    # Resolve dependencies in the worktree first. It has no `.dart_tool`, and
    # the test command carries `--no-pub`, so without this the first mutant
    # fails to run rather than resolving for itself.
    (cd "$WT/$pkg" && { flutter pub get >/dev/null 2>&1 || dart pub get >/dev/null 2>&1; }) \
        || fail "$pkg — could not resolve dependencies in the mutation worktree"

    # Time the suite on the UNMUTATED tree, once, and derive the per-mutant
    # timeout from it. mutation_test validates this baseline itself before it
    # mutates anything, so the run happens either way; measuring it here costs
    # one extra pass and buys a timeout that tracks the suite instead of a
    # number someone guessed in M0.
    #
    # Measured IN THE WORKTREE, which is where the mutants will run — and it is
    # a cold measurement there, which the derivation below already relies on
    # being safe: a cold baseline over-estimates, and over-estimating a timeout
    # only costs wall clock on a mutant that was going to fail anyway.
    baseline_start=$(date +%s)
    set +e
    (cd "$WT/$pkg" && eval "$test_cmd") >/dev/null 2>&1
    baseline_rc=$?
    set -e
    baseline_secs=$(( $(date +%s) - baseline_start ))
    [ "$baseline_rc" -eq 0 ] || fail "$pkg — the suite fails on the UNMUTATED tree.
       mutation_test would abort on its own baseline check and every mutant
       would read as undetected. Fix the suite first."

    # THE MEASUREMENT IS NOISY, AND EVERYTHING BELOW DERIVES FROM IT. Four runs
    # of `apps/mobile` on the same machine inside ~70 minutes measured 7, 19, 8
    # and 8 seconds, so an unclamped multiplier moves the failure boundary by
    # 2.7x between runs and no boundary can be stated. `packages/filefin_core`
    # is worse in the other direction: `date +%s` is integer seconds and that
    # suite finishes inside one, so the measurement is 0 or 1 and `run_cap`
    # collapsed to its 600 s floor for any diff under eight files — reproducing
    # the exact bug STATE.md:507 records as fixed, for two of the three
    # packages.
    #
    # Clamping the INPUT is the answer, and the argument for why noise above the
    # floor is harmless is the load-bearing half:
    #
    #   * The measurement is a COLD run by construction — first compile, cold
    #     package resolution — while every run mutation_test then makes is warm.
    #     So it over-estimates, and over-estimating a timeout only ever costs
    #     wall clock on a mutant that was going to fail anyway.
    #   * The only value that can be WRONG is therefore the smallest one the
    #     formula can install, and the floor fixes that at 12 x 5 = 60 s. The
    #     boundary is now checkable, which a value sliding between 84 and 228
    #     was not. Measured at M6.R on this machine: the `-400` cache-extent
    #     mutant in `media_grid.dart` — the worst legitimately-DETECTED one
    #     known, the whole reason 6 became 12 — takes **46 s** and prints
    #     3,676,139 lines, against a clean warm suite of **11 s** and 577.
    #     46 < 60, so even the floor clears it.
    #   * And the floor only ever BINDS for the pure-Dart packages, whose suites
    #     finish inside a second. Those have no render pipeline and so no
    #     I/O-storm case at all; `apps/mobile`, which does, measures 8 s cold and
    #     therefore installs 96 s. The value that could be too small is the one
    #     applied where the hazard does not exist.
    #   * A median of N was considered and rejected: N costs one extra full
    #     suite run each, and `apps/mobile`'s is ~8 s cold but the mutation run
    #     it feeds is 25 minutes. Paying minutes to smooth a number whose noise
    #     is already in the safe direction is the wrong trade.
    #
    # The ceiling is the mirror image: one pathological cold start (a machine
    # swapping, a cold CI image) must not install a half-hour per-mutant timeout
    # and a whole-run cap measured in days, because a gate that takes a day to
    # report is a gate nobody runs.
    [ "$baseline_secs" -lt 5 ] && baseline_secs=5
    [ "$baseline_secs" -gt 120 ] && baseline_secs=120

    # THE MULTIPLIER IS SIZED FOR A FAILING RUN, NOT A PASSING ONE, and that
    # distinction cost a false failure at M6.5. It was 6, and the assumption
    # under it — that a killed mutant costs about what a green suite costs — is
    # wrong whenever the mutant makes the render pipeline assert once per frame
    # instead of failing one expectation.
    #
    # Measured: `ScrollCacheExtent.pixels(400)` negated to `-400` in
    # `media_grid.dart` is DETECTED (eight tests fail), and the run takes
    # **42.7 s against a 42 s timeout** — 483 lines of output become 2,448,073,
    # of which 24,004 are "EXCEPTION CAUGHT BY SCHEDULER LIBRARY" with a full
    # stack each. Clean baseline on the same machine, same minute: 7.1 s. So the
    # ratio for a legitimately-detected mutant was 6.0 and the allowance was 6.
    # The gate then reported it as a HANG and told the reader to go looking for
    # an unbounded recursion that does not exist — a confidently wrong
    # diagnosis, which is worse than no diagnosis.
    #
    # 12 is twice the worst legitimate ratio measured. It is NOT a way of
    # hiding a loop: an infinite one burns the full timeout whatever it is, the
    # whole-run cap below still bounds the total, and the error message
    # distinguishes the two cases by pointing at the log size first.
    #
    # **THERE IS NO ENVIRONMENT OVERRIDE, and its removal at M6.R was the
    # point.** `FILEFIN_MUTANTS_TIMEOUT` existed from M5.R and was a fifth lever
    # CLAUDE.md's "three, and they are the complete list" did not mention. It
    # named itself nowhere in the output, had no bound in either direction — a
    # large enough value silently disables hang detection altogether — and
    # bypassed both the 12x derivation and the floor. The tooling gives; the
    # constitution does not take back. An override here re-opens exactly what
    # the clamp above closed, and raising the number is an edit in this file
    # that a reviewer sees in the diff.
    cmd_timeout=$(( baseline_secs * 12 ))
    [ "$cmd_timeout" -lt 60 ] && cmd_timeout=60
    echo "mutants: $pkg — suite baseline ${baseline_secs}s, per-mutant timeout ${cmd_timeout}s"

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<mutations version="1.1">'
        echo '  <commands>'
        # working-directory "." is the package: the run below cds there first.
        #
        # The timeout is DERIVED from this package's own clean-tree suite time,
        # not a fixed number. A mutant that loops forever costs exactly this
        # much wall clock, and it is charged once per looping mutant — so the
        # figure is the difference between a gate that reports in a minute and
        # one that appears to hang. It was 300s against suites that run in 1-7s;
        # a `||` rewritten to `&&` in front of a recursive retry burned the full
        # 300 and aborted every mutant behind it.
        #
        # **12x the measured baseline, floor 60s.** This comment said "6x,
        # floor 30s" until M6.R while the code four screens up computed 12 and
        # 60 — the 6 was replaced at M6.5 when a legitimately-DETECTED mutant
        # was measured at 6.0x and reported as a hang. There is no override;
        # the derivation and the clamp above are the whole story.
        printf '    <command group="test" expected-return="0" working-directory="." timeout="%s">%s</command>\n' "$cmd_timeout" "$test_cmd"
        echo '  </commands>'
        echo '  <files>'
        printf '%s\n' "$changed" | while IFS= read -r f; do
            case "$f" in "$pkg"/*) printf '    <file>%s</file>\n' "${f#"$pkg"/}" ;; esac
        done
        echo '  </files>'
        echo '</mutations>'
    } > "$targets"

    n=$(grep -c '<file>' "$targets" || true)
    echo "mutants: $pkg — $n changed lib file(s) vs $BASE"

    log="$tmpdir/run.log"
    set +e
    # NO `-b`. It adds mutation_test's builtin EXCLUSIONS as well as its rules,
    # and one of those (`[\s]for[\s]*\(.*?\)[\s]*{` with dotAll) swallows
    # everything after a Dart collection-for — 1,959 characters of engine.dart,
    # measured. Exclusions are additive and cannot be subtracted, so the builtin
    # rules are transcribed into mutation_rules.xml instead and this flag is
    # gone. Restoring it silently re-opens the hole; mutation_rules.xml carries
    # the retirement condition.
    # A whole-run cap on top of the per-mutant one. Even with a tight per-mutant
    # timeout, N looping mutants cost N times it, and a wedge inside
    # mutation_test itself is charged to nobody. `timeout` sends TERM then KILL,
    # so a wedged run FAILS rather than holding the gate open.
    #
    # **The budget is per MUTANT, and it used to be per FILE.** `n` is the
    # number of changed files, and the old line read
    # `(n * cmd_timeout + baseline_secs) * 2` while its own comment said "the
    # per-mutant timeout once per mutant" — so for any diff under eight files
    # the cap collapsed to the 600 s floor whatever the diff contained.
    # Measured at M6.4: extracting `file_list.dart` touched FOUR files, the
    # suite baseline was 7 s, and the run was killed at 600 s having not
    # finished — more than 85 mutants at ~7 s each, against a cap sized for
    # four. A gate that fails a healthy run is worse than no gate: it teaches
    # people to re-run it until it passes.
    #
    # A changed file yields tens of mutants, so the allowance is 40 per file at
    # the MEASURED baseline (a normal mutant costs one suite run; only a
    # looping one costs `cmd_timeout`), doubled for slack and still floored at
    # 10 minutes. The wedge this exists to catch is bounded either way; what
    # changes is that a large legitimate diff is no longer.
    mutant_budget=$(( n * 40 ))
    run_cap=$(( (mutant_budget * baseline_secs + baseline_secs) * 2 ))
    #
    # There is deliberately NO environment override for this number. An
    # undocumented lever that quietly raises a bound is a gate you have already
    # lost (CLAUDE.md's ratchet section), and raising it is an edit here that a
    # reviewer sees in the diff.
    [ "$run_cap" -lt 600 ] && run_cap=600
    (cd "$WT/$pkg" && timeout --kill-after=30s "${run_cap}s" \
        dart run mutation_test --rules "$RULES" -f none -o "$ROOT/.mutation-output" "$targets") \
        > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo "ERROR: $pkg — the mutation run exceeded its ${run_cap}s whole-run cap"
        echo "       and was killed. This is NOT a surviving mutant: the run did"
        echo "       not finish, so it measured nothing after the point it wedged."
        echo "       Usual cause: a mutant that makes the code loop forever — a"
        echo "       bound written as a condition in front of a recursive call,"
        echo "       where flipping the operator removes the bound. Find it with:"
        echo "         while :; do git -C $WT diff --stat; sleep 10; done"
        echo "       and look for the source that stays mutated. The fix is to"
        echo "       make the recursion structurally bounded (pass the budget as"
        echo "       an argument) rather than to widen this cap."
        status=1
        rm -rf "$tmpdir"
        continue
    fi
    cat "$log"

    # Zero mutants is NOT a pass, and this block used to say so in a comment
    # while printing a NOTICE and leaving `status` untouched — the gate agreeing
    # in prose that it had checked nothing, then reporting success.
    #
    # Two ways it happens, and both must fail: mutation_rules.xml excludes every
    # loop body and every ++/--, so a diff living entirely inside a loop yields
    # 0 mutants; and `found` is scraped from the literal string "Found N
    # mutations", so an upstream wording change pins it at 0 forever. A hard
    # failure turns the second one into a loud, one-line fix instead of a gate
    # that quietly stopped existing.
    found=$(grep -oE 'Found [0-9]+ mutations' "$log" | grep -oE '[0-9]+' | head -1 || echo 0)
    if [ "${found:-0}" -eq 0 ]; then
        if [ "${FILEFIN_MUTANTS_ALLOW_ZERO:-0}" = "1" ]; then
            echo "NOTICE: $pkg — 0 mutants, allowed by FILEFIN_MUTANTS_ALLOW_ZERO=1."
        else
            echo "ERROR: $pkg — the changed lines produced 0 mutants, so this run"
            echo "       asked nothing and 0-undetected-of-0 would read as 100%."
            echo "       Legitimate only for pure declarations (a const, a field, an"
            echo "       export). Otherwise: the exclusions in mutation_rules.xml are"
            echo "       swallowing the change, or mutation_test's 'Found N mutations'"
            echo "       wording moved and the scrape above is now always 0."
            echo "       Re-run with FILEFIN_MUTANTS_ALLOW_ZERO=1 only when you have"
            echo "       checked which, and say which in the commit message."
            status=1
        fi
    fi

    if [ "$rc" -ne 0 ]; then
        # mutation_test counts a timed-out mutant as "undetected", so the two
        # opposite meanings — "no test objected" and "the suite never finished"
        # — arrive as one number. This used to be a NOTE asking the reader to
        # work out which; a remediator who reads "1/62 undetected" as a real
        # survivor goes hunting for an assertion that does not exist. Scrape the
        # count and say which, because the gate knows and the reader does not.
        #
        # **ALL THREE NUMBERS ARE SCRAPED, AND UNTIL M6.R ONLY ONE WAS.** The
        # block read `Timeouts:` alone and `timeouts > 0` won unconditionally,
        # so a run reporting `Undetected Mutations: 8 / Timeouts: 1` — seven
        # genuine survivors and one hang — printed *"That is a HANG, not a
        # survivor … Do NOT go looking for a missing assertion"* while the
        # per-file survivor list sat in the `cat`-ed log directly above it. The
        # third distinct false diagnosis this script has produced this
        # milestone, and the worst kind: confident, specific, and wrong in the
        # direction that stops the reader looking.
        #
        # The arithmetic is upstream's own (`report_data.dart:155`):
        # `undetectedMutations = totalRuns - foundMutations`, so BOTH a timeout
        # and a not-covered mutation are counted as undetected. Subtracting them
        # is what leaves the real survivors.
        undetected=$(grep -oE 'Undetected Mutations: [0-9]+' "$log" | grep -oE '[0-9]+' | head -1 || echo 0)
        timeouts=$(grep -oE 'Timeouts: [0-9]+' "$log" | grep -oE '[0-9]+' | head -1 || echo 0)
        not_covered=$(grep -oE 'Not covered by tests: [0-9]+' "$log" | grep -oE '[0-9]+' | head -1 || echo 0)
        survivors=$(( ${undetected:-0} - ${timeouts:-0} - ${not_covered:-0} ))
        [ "$survivors" -lt 0 ] && survivors=0
        # mutation_test validates the suite on unmutated code before it mutates
        # anything, and aborts if that fails. Nothing was mutated, so there are
        # no survivors and no timeouts to scrape — and the first version of this
        # block printed "these are real survivors" over exactly that, which is
        # the confident-wrong-diagnosis this whole change exists to remove.
        # Found by proving the negative direction, not by reading the code.
        if grep -q 'failed with unmodified code' "$log"; then
            echo "ERROR: $pkg — the suite failed on UNMUTATED code, so mutation_test"
            echo "       aborted before mutating anything. There are no survivors and"
            echo "       no timeouts here: nothing was measured at all."
            echo "       Usual causes: the per-mutant timeout (${cmd_timeout}s) is"
            echo "       shorter than the suite's own runtime, or the suite is"
            echo "       genuinely red. Run the suite by hand first."
        else
            echo "ERROR: $pkg — ${undetected} undetected = ${survivors} surviving"
            echo "       mutant(s) + ${timeouts} timeout(s) + ${not_covered} not covered."
            echo "       THEY ARE DIFFERENT PROBLEMS AND A RUN CAN HAVE BOTH."
            if [ "$survivors" -gt 0 ]; then
                echo
                echo "       ${survivors} SURVIVOR(S). Each is a change to your code that no"
                echo "       test objects to. The per-file listing above names them"
                echo "       ('N not detected'). Add the assertion; exclude it in"
                echo "       mutation_rules.xml only if it is genuinely equivalent, with a"
                echo "       reason and a retirement condition."
            fi
            if [ "${timeouts:-0}" -gt 0 ]; then
                echo
                echo "       ${timeouts} mutant(s) hit the ${cmd_timeout}s per-mutant timeout."
                echo "       That is a HANG, not a survivor: the suite never finished, so"
                echo "       nothing was measured for those mutants."
                echo "       CHECK WHICH OF TWO THINGS IT IS BEFORE HUNTING A LOOP. A"
                echo "       mutant that is DETECTED but makes the render pipeline assert"
                echo "       once per frame prints tens of thousands of stack traces, and"
                echo "       the I/O alone can outrun this timeout — measured at M6.5, 483"
                echo "       lines of output against 2.4 million. Re-run the mutant by hand"
                echo "       and look at the line count: a loop produces almost none."
                echo "       Otherwise find the mutant that loops — most often a bound"
                echo "       written as a condition in front of a recursive call, where"
                echo "       flipping the operator removes the bound — and make the"
                echo "       recursion structurally bounded. Widening the timeout hides it"
                echo "       and costs the gate ${cmd_timeout}s per looping mutant, forever."
            fi
            if [ "${not_covered:-0}" -gt 0 ]; then
                echo
                echo "       ${not_covered} mutation(s) were reported as not covered by any"
                echo "       test, which is a survivor with a different name."
            fi
        fi
        status=1
    fi
    rm -rf "$tmpdir"
done

if [ "$status" -eq 0 ]; then
    echo "mutants: all mutants in the diff vs $BASE were killed"
fi
exit $status
