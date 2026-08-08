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

    targets="$(mktemp "${TMPDIR:-/tmp}/filefin-mutants-XXXXXX.xml")"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<mutations version="1.1">'
        echo '  <files>'
        printf '%s\n' "$changed" | while IFS= read -r f; do
            case "$f" in "$pkg"/*) printf '    <file>%s</file>\n' "${f#"$pkg"/}" ;; esac
        done
        echo '  </files>'
        echo '</mutations>'
    } > "$targets"

    n=$(grep -c '<file>' "$targets" || true)
    echo "mutants: $pkg — $n changed lib file(s) vs $BASE"

    log="$(mktemp "${TMPDIR:-/tmp}/filefin-mutants-XXXXXX.log")"
    set +e
    (cd "$pkg" && dart run mutation_test -b --rules "$RULES" -f none -o "$ROOT/.mutation-output" "$targets") \
        > "$log" 2>&1
    rc=$?
    set -e
    cat "$log"

    found=$(grep -oE 'Found [0-9]+ mutations' "$log" | grep -oE '[0-9]+' | head -1 || echo 0)
    if [ "${found:-0}" -eq 0 ]; then
        # Not a pass. Zero mutants means the run asked nothing, and 0 undetected
        # out of 0 reads as 100% success — exactly the shape of a gate that
        # congratulates you for checking nothing.
        echo "NOTICE: $pkg — the changed lines produced 0 mutants."
        echo "        That is legitimate only for pure declarations (a const, a"
        echo "        field, an export). If behaviour changed here, the exclusions"
        echo "        in mutation_rules.xml are swallowing it — check them."
    fi

    if [ "$rc" -ne 0 ]; then
        echo "ERROR: $pkg — surviving mutant(s). Each is a change to your code that"
        echo "       no test objects to. Add the assertion; exclude it in"
        echo "       mutation_rules.xml only if it is genuinely equivalent, with a"
        echo "       reason and a retirement condition."
        status=1
    fi
    rm -f "$targets" "$log"
done

if [ "$status" -eq 0 ]; then
    echo "mutants: all mutants in the diff vs $BASE were killed"
fi
exit $status
