#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Dependency gate (CLAUDE.md §4).
#
# §4 as written says every dependency has at least one `import` referencing it.
# Taken literally that is unsatisfiable: very_good_analysis is consumed by
# analysis_options.yaml, build_runner/freezed/json_serializable by the codegen
# step, coverage and mutation_test by gate recipes — none of them is ever
# imported by anything. So this script implements §4 as:
#
#   1. every declared dependency is imported as `package:<name>/` somewhere in
#      its own package, OR listed in tool/dep-allowlist.txt with a reason;
#   2. in BOTH cases the pubspec line is preceded by a `#` rent comment;
#   3. every `package:<name>/` import resolves to a declared dependency.
#
# Rule 2 is what stops the allowlist becoming a dumping ground: an entry there
# still has to say what needs it, in the pubspec, where the diff is reviewed.
# CLAUDE.md §4 records this reading.

ALLOWLIST="tool/dep-allowlist.txt"
exit_code=0
errors=0

allowlisted() {
    [ -f "$ALLOWLIST" ] || return 1
    grep -qE "^[[:space:]]*$1[[:space:]]*:" "$ALLOWLIST"
}

# Dependency names declared under `dependencies:` / `dev_dependencies:`, one
# per line as `<name> <line-number>`. `sdk:`-sourced entries (flutter,
# flutter_test) are real dependencies and are treated as such.
declared_deps() {
    awk '
        /^(dependencies|dev_dependencies):[[:space:]]*$/ { insec = 1; next }
        /^[^[:space:]#]/ { insec = 0 }
        insec && /^  [A-Za-z_][A-Za-z0-9_]*:/ {
            name = $1; sub(/:$/, "", name); print name, FNR
        }
    ' "$1"
}

# True when the line above the dependency pays rent — a `#` comment that says
# something. The comment must sit immediately above; a comment three lines up is
# attached to something else.
#
# The `[^[:space:]#]` is the point: a bare `#`, or a row of `###`, satisfied the
# old `^[[:space:]]*#` and paid no rent at all. §4 asks for a one-line reason,
# and an empty comment is not one.
has_rent_comment() {
    # `exit` inside a rule still runs END, so END must not override the status
    # — an `END { exit 1 }` here made every dependency look uncommented.
    awk -v n="$2" '
        FNR == n - 1 { ok = ($0 ~ /^[[:space:]]*#+[[:space:]]*[^[:space:]#]/); exit }
        END { exit ok ? 0 : 1 }
    ' "$1"
}

report() {
    echo "ERROR: $1"
    errors=$((errors + 1))
    exit_code=1
}

while IFS= read -r pubspec; do
    [ -n "$pubspec" ] || continue
    pkg_dir="$(dirname "$pubspec")"
    pkg_name="$(awk '/^name:/ { print $2; exit }' "$pubspec")"

    # A package's own sources: its lib/, test/, integration_test/, test_live/,
    # bin/, tool/, example/. The workspace root deliberately has none, which is
    # why all four of its tooling dev-dependencies live in the allowlist.
    #
    # `integration_test` joined the list at M2 with `just it`. Without it an
    # import in an integration suite was invisible to BOTH halves of this gate:
    # a package imported only there looked unused, and — worse — an *undeclared*
    # import there was never reported at all. Dart resolves an undeclared package
    # anyway when a sibling workspace member pulls it in, which is exactly how
    # one survives to break a clean checkout.
    #
    # `test_live` joined at M3 for the identical reason in a new location. The
    # app's live suite cannot live in `integration_test/`: `flutter test
    # integration_test` is routed to the device path by the tool, which then
    # demands a connected device. So the directory has a different name, and a
    # different name is a directory this gate had never heard of.
    srcs=()
    for sub in lib test integration_test test_live bin tool example; do
        [ -d "$pkg_dir/$sub" ] && srcs+=("$pkg_dir/$sub")
    done

    imported=""
    if [ ${#srcs[@]} -gt 0 ]; then
        imported=$(grep -rhoE "package:[a-z_][a-z0-9_]*/" "${srcs[@]}" --include='*.dart' 2>/dev/null \
            | sed 's|package:||; s|/$||' | sort -u || true)
    fi

    while read -r dep line; do
        [ -n "$dep" ] || continue
        if ! has_rent_comment "$pubspec" "$line"; then
            report "$pubspec:$line: dependency '$dep' has no rent comment — say in one line what needs it (§4)"
        fi
        if ! grep -qx "$dep" <<< "$imported"; then
            allowlisted "$dep" || report "$pubspec:$line: dependency '$dep' is never imported and is not in $ALLOWLIST (§4)"
        fi
    done < <(declared_deps "$pubspec")

    # Undeclared: something imports a package this pubspec does not list. Dart
    # resolves it anyway when a sibling workspace member pulls it in, which is
    # exactly how an undeclared dependency survives to break a clean checkout.
    declared_names=$(declared_deps "$pubspec" | awk '{print $1}')
    while IFS= read -r imp; do
        [ -n "$imp" ] || continue
        [ "$imp" = "$pkg_name" ] && continue
        grep -qx "$imp" <<< "$declared_names" || \
            report "$pubspec: 'package:$imp/' is imported under $pkg_dir but not declared (§4)"
    done <<< "$imported"
done < <(find . -name pubspec.yaml -not -path '*/.dart_tool/*' -not -path '*/build/*' | sort)

echo "dependencies: $errors error(s)"
exit $exit_code
