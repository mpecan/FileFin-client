#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Comment budget (CLAUDE.md §2). Two checks, and the FIRST one is the rule.
#
#   1. BLOCK CAP — no single comment block may exceed BLOCK_MAX lines.
#   2. RATIO     — comment lines as a share of non-blank lines, per file.
#
# WHY THE BLOCK CAP EXISTS, AND WHY THE RATIO ALONE COULD NOT DO ITS JOB.
#
# §2 counted `//` and excluded `///` from both sides of the ratio, on the
# reasoning that the budget is about narration and doc comments are API
# documentation. That reasoning was sound and the outcome was not: measured at
# M8.R, the tree was 3.8% `//` and 34.0% `///` — 37.9% comments overall — and
# this gate printed "0 error(s), 0 warning(s)" over it. The exclusion was not a
# blind spot the gate had, it was most of what there was to measure.
#
# Worse, the documented REMEDIATION exploited it. CLAUDE.md recorded that the
# three files breaching §2 at M3.R were paid "by moving the rationale into the
# `///` doc comment of the declaration it describes". Those files are 44-59%
# comments today. The fix was a change of comment syntax, and the gate has
# reported success on them ever since.
#
# So the numerator is now BOTH forms. But a ratio alone still cannot express
# what §2 is actually for. A file can sit at a healthy percentage while one
# declaration carries seventy lines of archaeology — `transport.dart` was
# 71 doc-comment lines over a 12-line function — and a file of terse one-line
# doc comments on every member can breach a percentage while being exactly
# what a reader wants. The ratio measures the wrong unit. The block does not:
#
#   a comment describing an INTERFACE is bounded by the interface,
#   and nothing with a bounded interface needs more than a dozen lines.
#
# Anything longer is a decision or a measurement, and both have somewhere to
# live: docs/decisions/ for choices we made, docs/field-notes.md for how a
# dependency or the server was observed to behave. The comment then cites it.
# That is the whole point — the prose is not deleted, it is moved somewhere it
# can be found by someone who is not already reading that declaration.
#
# BLOCK_MAX IS 12 AND THE NUMBER IS ARGUED, NOT GUESSED. Measured over
# non-generated lib sources at M8.R: a cap of 20 caught 37 blocks, 15 caught
# 72, 12 caught 119, 10 caught 156, 8 caught 199. Twelve is where the curve
# stops being about outliers — above it sit the essays, below it sit ordinary
# multi-paragraph member docs that are doing their job. It is also generous
# against its own justification: twelve lines is four sentences, which is more
# than any interface description in this repo has needed.
#
# THE RATIO IS MEASURED TREE-WIDE, NOT PER FILE, and that changed during M8.R
# on evidence. Per file it punishes the shape §2 is trying to produce: a file of
# short declarations each carrying a short doc comment scores enormously — after
# migration `ids.dart` was 81% (27 lines of comment over 33), being five
# `extension type` declarations one line long apiece with a sentence on each.
# Nothing about that file is wrong. `server_state.dart` at 47% and
# `auth_result.dart` at 42% are the same shape. Per file, the ratio's complaint
# correlates with declaration density rather than with verbosity, so it fires
# hardest exactly where the prose is already minimal.
#
# Tree-wide it measures what §2 is actually about — is this codebase turning
# into prose with code in it — and the per-file question is left to the block
# cap, which is exact at any size and does not care how dense the declarations
# around it are. Both checks survive; only the unit of the second one moved.
#
# THE THRESHOLDS MOVED TOO, BECAUSE THE NUMERATOR DID, and the old numbers
# cannot be carried over. 15/25 measured `//` against a denominator that
# excluded `///`; these measure both against everything. Comparing them is
# apples to oranges, and quoting the old pair would invite exactly that. They
# may fall, never rise (CLAUDE.md's ratchet).
#
# WORST_LISTED files are still printed with their percentage even when the tree
# passes. A gate that reports one number tells you nothing about where to look,
# and the per-file figure is useful information as long as it is not a verdict.
#
# Excluded from the ratio's numerator, and from the block cap:
#   - `// ignore:` / `// ignore_for_file:` — analyzer directives, not prose.
#     They are already justified by the lint they suppress.
#
# Scope is `dart_lib_sources`: test files are excluded because test narration
# is a feature, not debt (docs/architecture.md records this).
#
# THERE IS NO LONGER A MIN_LINES EXEMPTION, and its removal is the other half of
# going tree-wide. It existed because below twenty counted lines one comment
# moves a percentage by five points, so a per-file threshold could not be stated
# to the precision it was written at — a real problem, and CLAUDE.md §2 named
# the number so the exemption stayed visible. A tree-wide ratio has no such
# sensitivity (the denominator is the whole tree), and the block cap it also
# applied to is a count rather than a percentage, so it is exact at any file
# size. Nothing is skipped now, which means nothing has to be listed as skipped.

BLOCK_MAX=12
WARN_PCT=35
ERROR_PCT=45
WORST_LISTED=5

exit_code=0
errors=0
long_blocks=0
tree_comments=0
tree_total=0
worst=""

while IFS= read -r file; do
    [ -n "$file" ] || continue

    # THE BLOCK SCAN. A block is a maximal run of adjacent comment lines of the
    # SAME kind: a `///` run and a `//` run that touch are two blocks, because
    # they are two different things a reader is being told. A blank line ends a
    # block. Analyzer directives are invisible to it — a `// ignore:` sitting
    # inside a doc block must not join two halves into one long one, and must
    # not be a block of its own.
    while IFS= read -r offence; do
        [ -n "$offence" ] || continue
        echo "ERROR: $file:$offence"
        long_blocks=$((long_blocks + 1))
        errors=$((errors + 1))
        exit_code=1
    done < <(
        awk -v max="$BLOCK_MAX" '
            # ONE LINE PER OFFENCE. The caller reads this with `while read`, so
            # a message containing a newline is two offences to it: the first
            # draft wrapped the remedy onto a second line and the summary
            # reported 242 breaches over 119 blocks, with half the lines
            # carrying no line number. A gate that cannot count is a gate whose
            # ratchet means nothing.
            function flush() {
                if (kind != "" && n > max)
                    printf "%d — %s block is %d lines (max %d)\n", start, kind, n, max
                kind = ""; n = 0
            }
            {
                line = $0
                if (line ~ /^[[:space:]]*\/\/[[:space:]]*ignore(_for_file)?:/) next
                if (line ~ /^[[:space:]]*\/\/\//)      this = "doc"
                else if (line ~ /^[[:space:]]*\/\//)   this = "comment"
                else                                   this = ""
                if (this != kind) { flush(); kind = this; start = FNR; n = 0 }
                if (this != "") n++
            }
            END { flush() }
        ' "$file"
    )

    # THE RATIO. Numerator is every comment line, both forms. Denominator is
    # every non-blank line — doc comments included, which is the change: they
    # used to be subtracted from both sides, which is how 34% of the tree
    # became invisible to its own budget.
    read -r pct comments total < <(
        awk '
            {
                if ($0 ~ /^[[:space:]]*$/) next
                if ($0 ~ /^[[:space:]]*\/\/[[:space:]]*ignore(_for_file)?:/) next
                total++
                if ($0 ~ /^[[:space:]]*\/\//) comments++
            }
            END {
                total = total + 0; comments = comments + 0
                printf "%d %d %d\n", (total > 0 ? (comments * 100) / total : 0), comments, total
            }
        ' "$file"
    )

    tree_comments=$((tree_comments + comments))
    tree_total=$((tree_total + total))
    worst="${worst}${pct} ${comments} ${total} ${file}"$'\n'
done < <(dart_lib_sources)

tree_pct=0
[ "$tree_total" -gt 0 ] && tree_pct=$(( (tree_comments * 100) / tree_total ))

# Information, not a verdict — see the header. Printed on every run, passing or
# failing, because "the tree is at 31%" does not say where to look.
echo "comment budget: densest ${WORST_LISTED} file(s) —"
printf '%s' "$worst" | sort -rn | head -"$WORST_LISTED" |
    while read -r pct comments total file; do
        printf '       %3s%%  %s (%s/%s)\n' "$pct" "$file" "$comments" "$total"
    done

if [ "$tree_pct" -gt "$ERROR_PCT" ]; then
    echo "ERROR: the tree is ${tree_pct}% comments (${tree_comments}/${tree_total}, max ${ERROR_PCT}%)"
    errors=$((errors + 1))
    exit_code=1
elif [ "$tree_pct" -gt "$WARN_PCT" ]; then
    echo "WARN:  the tree is ${tree_pct}% comments (${tree_comments}/${tree_total}, target ${WARN_PCT}%)"
fi

if [ "$long_blocks" -gt 0 ]; then
    echo
    echo "       ${long_blocks} comment block(s) exceed the ${BLOCK_MAX}-line cap. A comment"
    echo "       describing an interface is bounded by that interface; anything"
    echo "       longer is a decision or a measurement. Move it to"
    echo "       docs/decisions/ (a choice we made) or docs/field-notes.md (how a"
    echo "       dependency or the server was observed to behave), and leave a"
    echo "       one-line citation behind. Do not delete it and do not reword it"
    echo "       shorter in place — the prose is the asset, its location is the bug."
fi

echo "comment budget: tree ${tree_pct}% (warn ${WARN_PCT} / error ${ERROR_PCT}), ${long_blocks} block(s) over the ${BLOCK_MAX}-line cap, $errors error(s)"
exit $exit_code
