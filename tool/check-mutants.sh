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

if strip_xml_comments "$RULES" | grep -q '<commands>'; then
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

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<mutations version="1.1">'
        echo '  <commands>'
        # working-directory "." is the package: the run below cds there first.
        # The 300s timeout is the one the NOTE at the bottom of this script
        # refers to — a mutant killed by it is counted "undetected" and reads
        # like a real survivor.
        printf '    <command group="test" expected-return="0" working-directory="." timeout="300">%s</command>\n' "$test_cmd"
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
    (cd "$pkg" && dart run mutation_test --rules "$RULES" -f none -o "$ROOT/.mutation-output" "$targets") \
        > "$log" 2>&1
    rc=$?
    set -e
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
        echo "ERROR: $pkg — surviving mutant(s). Each is a change to your code that"
        echo "       no test objects to. Add the assertion; exclude it in"
        echo "       mutation_rules.xml only if it is genuinely equivalent, with a"
        echo "       reason and a retirement condition."
        # mutation_test's own per-file report cannot tell the two apart, and a
        # remediator who reads "1/62 undetected" as a real survivor goes looking
        # for a missing assertion that does not exist. Observed: a run killed by
        # the 300s command timeout reported exactly that; the same tree run to
        # completion reported 62/62. Failing safe when interrupted is right —
        # this line is so the reader knows which happened.
        echo "NOTE:  a mutant killed by the 300s command timeout (set above) is"
        echo "       also counted 'undetected'. If the log above shows a timeout, the"
        echo "       run was interrupted rather than a mutant surviving — re-run"
        echo "       on a quiescent machine before hunting for a missing test."
        status=1
    fi
    rm -rf "$tmpdir"
done

if [ "$status" -eq 0 ]; then
    echo "mutants: all mutants in the diff vs $BASE were killed"
fi
exit $status
