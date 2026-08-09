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
# Nothing else may read those files while it runs, which is why `just check`
# lists this gate last and why just's sequential dependency execution matters.
# Do not parallelise it with another gate.
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

    # Time the suite on the UNMUTATED tree, once, and derive the per-mutant
    # timeout from it. mutation_test validates this baseline itself before it
    # mutates anything, so the run happens either way; measuring it here costs
    # one extra pass and buys a timeout that tracks the suite instead of a
    # number someone guessed in M0.
    baseline_start=$(date +%s)
    set +e
    (cd "$pkg" && eval "$test_cmd") >/dev/null 2>&1
    baseline_rc=$?
    set -e
    baseline_secs=$(( $(date +%s) - baseline_start ))
    [ "$baseline_rc" -eq 0 ] || fail "$pkg — the suite fails on the UNMUTATED tree.
       mutation_test would abort on its own baseline check and every mutant
       would read as undetected. Fix the suite first."

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
    cmd_timeout="${FILEFIN_MUTANTS_TIMEOUT:-}"
    if [ -z "$cmd_timeout" ]; then
        cmd_timeout=$(( baseline_secs * 12 ))
        [ "$cmd_timeout" -lt 60 ] && cmd_timeout=60
    fi
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
        # 6x the measured baseline, floor 30s: generous enough for a loaded
        # machine or a cold VM, tight enough that a loop is obvious. Override
        # with FILEFIN_MUTANTS_TIMEOUT when a genuinely slow suite needs it, and
        # say why in the commit.
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
    (cd "$pkg" && timeout --kill-after=30s "${run_cap}s" \
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
        echo "         while :; do git -C $pkg diff --stat; sleep 10; done"
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
        timeouts=$(grep -oE 'Timeouts: [0-9]+' "$log" | grep -oE '[0-9]+' | head -1 || echo 0)
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
        elif [ "${timeouts:-0}" -gt 0 ]; then
            echo "ERROR: $pkg — ${timeouts} mutant(s) hit the ${cmd_timeout}s per-mutant"
            echo "       timeout. That is a HANG, not a survivor: the suite never"
            echo "       finished, so nothing was measured for those mutants."
            echo "       CHECK WHICH OF TWO THINGS IT IS BEFORE HUNTING A LOOP. A"
            echo "       mutant that is DETECTED but makes the render pipeline assert"
            echo "       once per frame prints tens of thousands of stack traces, and"
            echo "       the I/O alone can outrun this timeout — measured at M6.5, 483"
            echo "       lines of output against 2.4 million. Re-run the mutant by hand"
            echo "       and look at the line count: a loop produces almost none."
            echo "       Do NOT go looking for a missing assertion. Find the mutant"
            echo "       that loops — most often a bound written as a condition in"
            echo "       front of a recursive call, where flipping the operator"
            echo "       removes the bound — and make the recursion structurally"
            echo "       bounded. Widening the timeout hides it and costs the gate"
            echo "       ${cmd_timeout}s per looping mutant, every run, forever."
        else
            echo "ERROR: $pkg — surviving mutant(s). Each is a change to your code that"
            echo "       no test objects to. Add the assertion; exclude it in"
            echo "       mutation_rules.xml only if it is genuinely equivalent, with a"
            echo "       reason and a retirement condition."
            echo "       (Timeouts: 0 — so these are real survivors, not a wedged run.)"
        fi
        status=1
    fi
    rm -rf "$tmpdir"
done

if [ "$status" -eq 0 ]; then
    echo "mutants: all mutants in the diff vs $BASE were killed"
fi
exit $status
