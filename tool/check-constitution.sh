#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Mechanical checks for the constitutional stipulations that prose alone does
# not deliver (CLAUDE.md §1, §5, §6, §7, §8, §9).
#
# A RATCHET, not a pass/fail gate:
#   count > baseline   ERROR  — a new violation was introduced
#   count == baseline  ok     — existing debt, unchanged
#   count < baseline   NOTICE — debt paid; run `just constitution-accept`
#
# Every count starts at 0 and the baseline may only ever move down, so at this
# stage the ratchet and a hard gate behave identically. The ratchet machinery
# exists now anyway, because a baseline retrofitted after the first violation
# lands is a baseline that legitimises it.
#
# Usage: check-constitution.sh [check|accept]

BASELINE="tool/constitution-baseline.txt"
MODE="${1:-check}"
CORE_LIB="packages/filefin_core/lib"

# --- checks -----------------------------------------------------------------
# Each prints one line per violation; the line count is the metric. Each ends
# with `|| true` so grep's "no matches" exit 1 is not mistaken for a failure by
# `set -e` — a check that aborts the script reports nothing and looks clean.

# §1: no stubs, no deferred work markers. Something you meant to finish is
# either finished or it is not in the tree.
check_placeholders() {
    local files
    files=$(dart_lib_sources)
    [ -n "$files" ] || return 0
    grep -nHE 'UnimplementedError|TODO:|FIXME' $files || true
}

# §6: filefin_core is I/O-free, Flutter-free and deterministic. Two halves,
# because either alone is evadable: the import scan catches code that reaches
# for the outside world, the pubspec scan catches a dependency that would let
# it (a package listed but not yet imported is tomorrow's violation).
check_core_purity() {
    if [ -d "$CORE_LIB" ]; then
        local files
        files=$(find "$CORE_LIB" -name '*.dart' -not -name '*.g.dart' -not -name '*.freezed.dart')
        if [ -n "$files" ]; then
            grep -nHE "package:flutter|dart:io|dart:ui|package:http|package:dio|DateTime\.now\(|Random\(|Stopwatch\(" $files || true
        fi
    fi
    local pubspec="packages/filefin_core/pubspec.yaml"
    if [ -f "$pubspec" ]; then
        grep -nE '^[[:space:]]+(flutter|http|dio|dio_cookie_manager):' "$pubspec" || true
    fi
}

# §7: IDs are extension types, never typedefs. A typedef gives a CategoryId
# exactly where a MediaId is expected — and they are not even the same
# primitive, so the server answers the mix-up with a 404 rather than an error.
check_id_typedefs() {
    local files
    files=$(dart_sources)
    [ -n "$files" ] || return 0
    grep -nHE '^[[:space:]]*typedef[[:space:]]+(MediaId|CategoryId|FileIndex|SubtitleIndex|ServerId)[[:space:]]*=' $files || true
}

# §5: a sealed-class variant nobody constructs is dead. `analyze` will not tell
# you — an unconstructed public class is not unused code to the analyzer.
#
# "Constructed" means named outside the file that declares it; a variant used
# only by its own declaring file has no consumer.
check_dead_types() {
    local files
    files=$(dart_sources)
    [ -n "$files" ] || return 0

    local sealed_names
    sealed_names=$(grep -hoE '^[[:space:]]*(abstract[[:space:]]+)?sealed[[:space:]]+class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $files 2>/dev/null \
        | awk '{print $NF}' | sort -u)
    [ -n "$sealed_names" ] || return 0

    local decl name base file others
    while IFS= read -r decl; do
        [ -n "$decl" ] || continue
        file="${decl%%:*}"
        name=$(echo "${decl#*:}" | awk '{print $3}')
        base=$(echo "${decl#*:}" | awk '{print $5}')
        grep -qx "$base" <<< "$sealed_names" || continue
        others=$(printf '%s\n' $files | grep -vx "$file" || true)
        if [ -z "$others" ] || ! grep -qE "\b${name}[[:space:]]*\(" $others 2>/dev/null; then
            echo "$file: sealed variant '$name' is never constructed outside its own file"
        fi
    done < <(grep -nE '^[[:space:]]*final[[:space:]]+class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+extends[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $files 2>/dev/null | sed 's/:[0-9]*:/:/' || true)
}

# §8: every endpoint we call is documented with its upstream citation. The
# grep is over string literals starting `/api/`, which is why M1.6 puts every
# route in one `ApiPaths` class — one place to keep honest.
check_undocumented_endpoint() {
    local files doc path
    files=$(dart_lib_sources)
    [ -n "$files" ] || return 0
    doc="docs/server-api.md"
    if [ ! -f "$doc" ]; then
        grep -nHE "'/api/" $files || true
        return 0
    fi
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        grep -qF "$path" "$doc" || echo "$path: not documented in $doc"
    done < <(grep -hoE "'/api/[^']*'" $files 2>/dev/null | tr -d "'" | sort -u)
}

# §9: a secret-bearing type must override toString(). freezed's generated
# toString prints every field, so a Session or Credential that forgets this
# leaks its own contents into the first log line that interpolates it.
check_secret_tostring() {
    local files
    files=$(dart_lib_sources)
    [ -n "$files" ] || return 0
    awk '
        /^[[:space:]]*(abstract[[:space:]]+|sealed[[:space:]]+|final[[:space:]]+|base[[:space:]]+)*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/ {
            for (i = 1; i <= NF; i++) if ($i == "class") { cname = $(i + 1); break }
            sub(/[<({].*/, "", cname)
            if (cname ~ /(Credential|Password|Secret|Session|Token)/) {
                inclass = 1; depth = 0; seen = 0; start = FNR; watched = cname
            }
            next
        }
        inclass {
            if ($0 ~ /String[[:space:]]+toString[[:space:]]*\(/) seen = 1
            n = gsub(/{/, "{"); depth += n
            n = gsub(/}/, "}"); depth -= n
            if (depth <= 0 && index($0, "}") > 0) {
                if (!seen) printf "%s:%d: class %s bears a secret but does not override toString()\n", FILENAME, start, watched
                inclass = 0
            }
        }
    ' $files || true
}

CHECKS="placeholders core_purity id_typedefs dead_types undocumented_endpoint secret_tostring"

# --- ratchet ----------------------------------------------------------------

baseline_for() {
    [ -f "$BASELINE" ] || { echo 0; return; }
    local n
    n=$(awk -v k="$1" '$1 == k { print $2 }' "$BASELINE")
    echo "${n:-0}"
}

if [ "$MODE" = "accept" ]; then
    for c in $CHECKS; do
        new=$("check_$c" | grep -c . || true)
        old=$(baseline_for "$c")
        if [ "$new" -gt "$old" ]; then
            echo "WARNING: $c rises $old -> $new. Accepting new debt, not paying it."
        fi
    done
    {
        echo "# Constitutional debt baseline — see tool/check-constitution.sh"
        echo "# These counts may only ever decrease. Regenerate: just constitution-accept"
        for c in $CHECKS; do
            echo "$c $("check_$c" | grep -c . || true)"
        done
    } > "$BASELINE"
    echo "baseline written to $BASELINE:"
    grep -v '^#' "$BASELINE" | sed 's/^/  /'
    exit 0
fi

exit_code=0
improved=0

for c in $CHECKS; do
    output=$("check_$c")
    count=$(printf '%s' "$output" | grep -c . || true)
    base=$(baseline_for "$c")

    if [ "$count" -gt "$base" ]; then
        echo "ERROR: $c — $count violation(s), baseline $base: a new one was introduced"
        printf '%s\n' "$output" | sed 's/^/       /'
        exit_code=1
    elif [ "$count" -lt "$base" ]; then
        echo "NOTICE: $c — $count violation(s), down from $base. Debt paid."
        improved=1
    elif [ "$count" -gt 0 ]; then
        echo "debt:  $c — $count violation(s), unchanged"
    fi
done

if [ "$improved" -eq 1 ]; then
    echo
    echo "Ratchet moved down. Lock it in: just constitution-accept"
fi

if [ "$exit_code" -eq 0 ]; then
    echo "constitution: no new violations"
fi
exit $exit_code
