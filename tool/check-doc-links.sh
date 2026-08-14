#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Every relative link in the documentation resolves to something that exists.
#
# This gate is the same argument §2 makes about comments, applied to the files
# that are all reference: a pointer that can rot is a liability, and the only
# two answers are to remove it or to check it. Comments took the first answer.
# A README cannot — its whole job is to point at things — so it takes the
# second.
#
# The rot is not hypothetical. The M8.R review found the entry point missing
# entirely, and the documents that did exist referred to `docs/architecture.md`
# sections and D-numbers that had moved. A README that sends a newcomer to a
# path that no longer exists is worse than one that says nothing, because it
# spends their trust before it spends their time.
#
# SCOPE: markdown link targets that are RELATIVE PATHS. Deliberately not:
#   - `http(s)://` — a network call in a gate makes it fail when the network
#     does, which is a gate that fails for reasons unrelated to the tree;
#   - bare `#anchor` links — resolving those means parsing headings, and the
#     failure mode (a wrong anchor) is visibly harmless next to a dead path;
#   - anything inside a fenced code block, which is illustration, not a link.
#
# A path with an `#anchor` suffix is checked without it: the file must exist,
# the anchor is not our problem.

DOCS=(README.md CONTRIBUTING.md CLAUDE.md SPEC.md docs/decisions/README.md)

errors=0
checked=0

for doc in "${DOCS[@]}"; do
    [ -f "$doc" ] || fail "$doc does not exist, and this gate names it explicitly.
       Either restore it or remove it from DOCS in this script — a gate that
       silently skips a missing file is a gate that stopped existing."
    dir="$(dirname "$doc")"

    # Strip fenced code blocks first: a sample command containing something that
    # looks like a link is not a link, and failing on one would teach people to
    # stop writing examples.
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        case "$target" in
            http://*|https://*|mailto:*|'#'*) continue ;;
        esac
        checked=$((checked + 1))
        path="${target%%#*}"
        [ -n "$path" ] || continue
        # Relative to the document that carries the link, as markdown resolves it.
        if [ ! -e "$dir/$path" ] && [ ! -e "$path" ]; then
            echo "ERROR: $doc links to '$target', which does not exist"
            errors=$((errors + 1))
        fi
    done < <(
        awk '/^```/ { fence = !fence; next } !fence { print }' "$doc" \
            | grep -oE '\]\([^)]+\)' \
            | sed -e 's/^](//' -e 's/)$//'
    )
done

echo "doc links: $checked relative link(s) across ${#DOCS[@]} document(s), $errors broken"
[ "$errors" -eq 0 ] || exit 1
