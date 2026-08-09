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
#
# EVERY file list is carried in an ARRAY and expanded as "${files[@]}", never as
# a bare `$files`. An unquoted expansion word-splits on IFS, which includes the
# space, so `packages/x/lib/my file.dart` reached grep as two paths that do not
# exist — and the `|| true` above swallowed grep's complaint, so all six checks
# reported "no violations" and the gate exited 0. That is the single worst shape
# a gate can have (CLAUDE.md, "Gates must be able to fail"), and it is why the
# read-into-array loop below is repeated rather than shortened.

# Read a newline-separated file list into the array named by $1. Bash 3.2 has no
# `mapfile`, and a nameref needs 4.3, so the caller passes the array by doing the
# loop itself; this comment is the shared explanation.
#
# §1: no stubs, no deferred work markers. Something you meant to finish is
# either finished or it is not in the tree.
check_placeholders() {
    local files=() f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(dart_lib_sources)
    if [ ${#files[@]} -eq 0 ]; then return 0; fi
    grep -nHE 'UnimplementedError|TODO:|FIXME' "${files[@]}" || true
}

# §6: filefin_core is I/O-free, Flutter-free and deterministic. Two halves,
# because either alone is evadable: the import scan catches code that reaches
# for the outside world, the pubspec scan catches a dependency that would let
# it (a package listed but not yet imported is tomorrow's violation).
#
# TWO SCOPES, because two different claims are being enforced.
#
# `filefin_core` is I/O-free AND deterministic: no dart:io, no HTTP client, no
# ambient clock or randomness. That is §6 as written.
#
# Every OTHER pure-Dart package — `filefin_api` today — claims only to be
# **Flutter-free**, and until M2's review that claim was prose. `CORE_LIB` was
# hard-coded here, so the scan never looked at `filefin_api` at all and the
# sentence in its pubspec was enforced by nobody. It is true today (measured: no
# flutter/flutter_test/sky_engine in either pubspec.lock, no `package:flutter`
# or `dart:ui` import anywhere), and a claim that is true and unenforced is a
# claim that stops being true in a commit nobody reads twice. `filefin_api` DOES
# use dart:io and dio — F15 cannot exist without them — so the determinism half
# stays core-only rather than being watered down for both.
#
# Membership is decided by LOCATION, and deliberately not by the pubspec.
# `packages/` is pure Dart and `apps/` is where Flutter lives (§6, and
# docs/architecture.md). A rule keyed on "does this pubspec depend on flutter?"
# exempts a package the moment it adds the dependency, which is the one moment
# the rule exists for — measured while writing this: adding `flutter: {sdk:
# flutter}` to filefin_api's pubspec made that version of the check go green.
check_core_purity() {
    local pkg lib pubspec files=() f
    for pubspec in packages/*/pubspec.yaml; do
        [ -f "$pubspec" ] || continue
        pkg="$(dirname "$pubspec")"
        lib="$pkg/lib"
        if [ -d "$lib" ]; then
            files=()
            while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done \
                < <(find "$lib" -name '*.dart' -not -name '*.g.dart' -not -name '*.freezed.dart')
            if [ ${#files[@]} -gt 0 ]; then
                if [ "$lib" = "$CORE_LIB" ]; then
                    grep -nHE "package:flutter|dart:io|dart:ui|package:http|package:dio|DateTime\.now\(|Random\(|Stopwatch\(" "${files[@]}" || true
                else
                    grep -nHE "package:flutter|dart:ui" "${files[@]}" || true
                fi
            fi
        fi
        if [ "$lib" = "$CORE_LIB" ]; then
            grep -nE '^[[:space:]]+(flutter|http|dio|dio_cookie_manager):' "$pubspec" || true
        else
            grep -nE '^[[:space:]]+flutter:' "$pubspec" || true
        fi
    done
}

# §7: IDs are extension types, never typedefs. A typedef gives a CategoryId
# exactly where a MediaId is expected — and they are not even the same
# primitive, so the server answers the mix-up with a 404 rather than an error.
check_id_typedefs() {
    local files=() f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(dart_sources)
    if [ ${#files[@]} -eq 0 ]; then return 0; fi
    grep -nHE '^[[:space:]]*typedef[[:space:]]+(MediaId|CategoryId|FileIndex|SubtitleIndex|ServerId)[[:space:]]*=' "${files[@]}" || true
}

# §5: a sealed-class variant nobody constructs is dead. `analyze` will not tell
# you — an unconstructed public class is not unused code to the analyzer.
#
# "Constructed" means named outside the file that declares it; a variant used
# only by its own declaring file has no consumer.
#
# The variant's class modifier is OPTIONAL. This check originally required
# `final class X extends Y`, so the byte-identical hierarchy written as plain
# `class X extends Y` was invisible — Dart permits it and `analyze` does not
# object, which made the rule evadable by deleting one keyword.
#
# `sealed` and `abstract` are deliberately NOT in the modifier set: neither can
# be constructed at all, so "never constructed" is not a violation for them, it
# is the definition. Flagging them would be a false positive on every
# intermediate node of a nested hierarchy.
#
# TYPE PARAMETERS ARE OPTIONAL EVERYWHERE, and they were not until M3.4. The
# declaration pattern required `class Name extends Base` with a space before
# `extends`, so `final class EmptyBox<T> extends Box<T>` matched NOTHING and a
# generic sealed hierarchy was exempt from §5 in its entirety. Measured before
# the fix on a probe: the generic form exited 0, the byte-identical
# non-generic form exited 1. M3 introduces the tree's first generic sealed
# hierarchy (`UiState<T>`), so the gate would have stopped covering the rule
# exactly when the rule started to matter — the same shape as the `interface`/
# `mixin` modifiers that were missing at M2.
#
# The construction search carries the same allowance: `UiData<int>(…)` is a
# construction and `\bUiData[[:space:]]*\(` does not match it.
#
# **THE DECLARATION IS A LOGICAL LINE, NOT A PHYSICAL ONE, and that is not a
# hypothetical.** Until M3.R the match ran per physical line, so a header
# `dart format` had wrapped —
#
#     final class SomethingRatherLong<T>
#         extends Base<T> {
#
# — matched nothing and the variant was exempt from §5 entirely. `dart format`
# is mandatory here (`just fmt-check`) and it produced exactly that shape
# unprompted from a one-line declaration over 80 columns; generics widen
# declarations, so M3's first generic sealed hierarchy makes it likelier, not
# less. The header is now accumulated until the `{` (or the `;` of a class
# alias) before it is matched at all.
#
# **`implements` counts as well as `extends`.** A sealed hierarchy's variants
# can only be declared in the same library, and `implements Base` is a legal
# and common way to write one — it was silently exempt.
#
# Generics are erased before the words are read, innermost-first, so a nested
# bound (`class X<T extends Map<String, int>> extends Base<T>`) cannot hide the
# real `extends` behind the one inside the type-parameter list.
check_dead_types() {
    local files=() f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(dart_sources)
    if [ ${#files[@]} -eq 0 ]; then return 0; fi

    local sealed_names
    sealed_names=$(grep -hoE '^[[:space:]]*(abstract[[:space:]]+)?sealed[[:space:]]+class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "${files[@]}" 2>/dev/null \
        | awk '{print $NF}' | sort -u)
    [ -n "$sealed_names" ] || return 0

    local file name base others g
    while IFS=$'\t' read -r file name base; do
        [ -n "$name" ] || continue
        grep -qx "$base" <<< "$sealed_names" || continue
        others=()
        for g in "${files[@]}"; do
            [ "$g" = "$file" ] || others+=("$g")
        done
        if [ ${#others[@]} -eq 0 ] \
            || ! grep -qE "\b${name}(<.*>)?[[:space:]]*\(" "${others[@]}" 2>/dev/null; then
            echo "$file: sealed variant '$name' is never constructed outside its own file"
        fi
    done < <(awk -v sealed="$(tr '\n' ' ' <<< "$sealed_names")" '
        # SPACE-separated, not newline-separated: BSD awk refuses a `-v` value
        # containing a newline outright ("newline in string"), and the refusal
        # goes to stderr — which this call sends to /dev/null, so the first
        # draft of this fix reported ZERO violations on a probe file carrying
        # six of them and looked like it was passing.
        BEGIN {
            n = split(sealed, s, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (s[i] != "") isSealed[s[i]] = 1
        }
        # Erase generics innermost-first, so `<T extends Map<String, int>>`
        # disappears whole rather than leaving a dangling `>`.
        function degeneric(t,   prev) {
            do { prev = t; gsub(/<[^<>]*>/, "", t) } while (t != prev)
            return t
        }
        function emit(buf,   decl, k, w, i, cname, bname, cand) {
            sub(/[{;].*/, "", buf)
            decl = degeneric(buf)
            gsub(/,/, " ", decl)
            k = split(decl, w, /[[:space:]]+/)
            cname = ""; bname = ""
            for (i = 1; i <= k; i++) if (w[i] == "class") { cname = w[i + 1]; break }
            for (i = 1; i <= k; i++) if (w[i] == "extends") { bname = w[i + 1]; break }
            # `extends` wins when it names a sealed base; otherwise every name
            # in the `implements` clause is a candidate, because that is the
            # other legal way to declare a variant.
            if (cname != "" && !(bname in isSealed)) {
                cand = 0
                for (i = 1; i <= k; i++) {
                    if (w[i] == "implements") cand = 1
                    else if (w[i] == "with" || w[i] == "extends") cand = 0
                    else if (cand && w[i] in isSealed) { bname = w[i]; break }
                }
            }
            if (cname != "" && bname != "") printf "%s\t%s\t%s\n", FILENAME, cname, bname
        }
        # The modifier set is enumerated rather than `[a-z]+`, and `sealed` and
        # `abstract` are still deliberately absent from it: neither can be
        # constructed at all, so "never constructed" is their definition rather
        # than a violation. Measured — a permissive `[a-z]+` reported the
        # intermediate `sealed class PlayNow extends PlaybackDecision` as debt.
        FNR == 1 { buf = "" }
        {
            if (buf != "") buf = buf " " $0
            else if ($0 ~ /^[[:space:]]*((final|base|interface|mixin)[[:space:]]+)*class[[:space:]]/) buf = $0
            if (buf != "" && buf ~ /[{;]/) { emit(buf); buf = "" }
        }
    ' "${files[@]}" 2>/dev/null || true)
}

# Collapse every placeholder to the single token `{}` so a Dart interpolation
# and the doc's prose placeholder compare equal. `'/api/media/$id'` and the
# doc's `/api/media/{id}` are the same route; a verbatim `grep -qF` between them
# never matches, which would have made this check fail on correct code the day
# M1.6 wrote its first parameterised path.
#
# Order matters: `${expr}` before `$ident`, both before `{name}`.
normalise_api_paths() {
    sed -E 's/\$\{[^}]*\}/{}/g; s/\$[A-Za-z_][A-Za-z0-9_]*/{}/g; s/\{[^{}]*\}/{}/g'
}

# §8: every endpoint we call is documented with its upstream citation. The scan
# is over string literals *containing* `/api/` — not only those starting with
# it. `'$base/api/media/$id'` is how `filefin_api` will actually build a
# request, and anchoring at the start of the literal made exactly that shape
# invisible. Double-quoted literals count too.
#
# Known limit, stated rather than papered over: a path split across adjacent
# concatenated literals (`'/api/' 'media'`) is not reconstructed. M1.6 puts
# every route in one `ApiPaths` class, which is the structural answer.
check_undocumented_endpoint() {
    local files=() f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(dart_lib_sources)
    if [ ${#files[@]} -eq 0 ]; then return 0; fi

    local doc="docs/server-api.md" doc_norm="" path
    if [ -f "$doc" ]; then
        doc_norm="$(mktemp "${TMPDIR:-/tmp}/filefin-apidoc-XXXXXX")"
        normalise_api_paths < "$doc" > "$doc_norm"
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -z "$doc_norm" ]; then
            echo "$path: $doc does not exist, so no endpoint is documented"
        elif ! grep -qF "$path" "$doc_norm"; then
            echo "$path: not documented in $doc"
        fi
    done < <(
        grep -hoE "'[^']*'|\"[^\"]*\"" "${files[@]}" 2>/dev/null \
            | grep -F '/api/' \
            | sed -E "s/^['\"]//; s/['\"]\$//; s|^.*(/api/)|\1|" \
            | normalise_api_paths \
            | grep -E '^/api/.' \
            | sort -u
    )

    [ -n "$doc_norm" ] && rm -f "$doc_norm"
    return 0
}

# §9: a secret-bearing type must override toString(). freezed's generated
# toString prints every field, so a Session or Credential that forgets this
# leaks its own contents into the first log line that interpolates it.
#
# The override must be a DECLARATION, not a mention. Matching
# `String\s+toString\s*\(` anywhere on any line meant the line
# `// We deliberately do not write String toString() here.` satisfied §9 — a
# rule answerable in prose is not a rule. Comment lines are skipped and the
# match is anchored to the declaration shape.
#
# The modifier alternation must list EVERY modifier Dart allows before `class`,
# because the pattern is what decides whether the class is looked at at all — a
# missing keyword is not a weaker check, it is no check. Measured at M2:
# `interface` and `mixin` were absent, so `abstract interface class TokenStore`
# matched nothing and was exempt from §9 entirely while the byte-identical
# `class TokenStore` was flagged. The secret-store port is an
# `abstract interface class`, which is how this was found.
#
# Two shapes are still NOT covered, and that is a decision rather than an
# oversight. A bare `mixin Foo` has no planned instance in this tree. An `enum`
# is deliberately excluded: `SecretKind` is an enum whose name matches `Secret`
# and whose default `toString` prints `SecretKind.session` — a key discriminator
# carrying no secret at all — so including enums would force a meaningless
# override onto correct code, which is how a gate teaches people to route around
# it. Revisit if an enum ever holds a value rather than naming one.
check_secret_tostring() {
    local files=() f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(dart_lib_sources)
    if [ ${#files[@]} -eq 0 ]; then return 0; fi
    awk '
        # Braces are counted on a line with its STRINGS AND COMMENTS REMOVED,
        # and a class still open at the end of a file is REPORTED. Both halves
        # are load-bearing and both were missing at M2, where seeding `depth`
        # from the declaration line fixed three false positives and bought a
        # class of silent false NEGATIVES: `inclass` was only ever cleared by
        # seeing depth return to zero, with no END rule and no per-file reset,
        # so one brace the counter should never have seen made the class vanish
        # from the check entirely. Dart is brace-balanced, so the only way to
        # unbalance it is a brace inside a string or a comment — all four of
        # these are ordinary Dart, and all four made a secret-bearing class with
        # NO toString() pass:
        #
        #     static const template = "Bearer {";
        #     // ... we open a brace here: {
        #     ///     if (x) {                     (a doc-comment sample)
        #     static final re = RegExp(r"^\{");
        #
        # Known limits, stated rather than papered over: a triple-quoted string
        # and a multi-line /* */ comment are not tracked across lines, and a
        # single-line class body is dropped. Every one of them now FAILS CLOSED
        # — the flush turns a missed close into a report on a class that has no
        # toString, instead of into silence.
        function bare(s,   t) {
            t = s
            gsub(/\\./, "", t)
            gsub(/'"'"'[^'"'"']*'"'"'/, "", t)
            gsub(/"[^"]*"/, "", t)
            gsub(/\/\*[^*]*\*\//, "", t)
            sub(/\/\/.*/, "", t)
            return t
        }
        function flush(file) {
            if (inclass && !seen)
                printf "%s:%d: class %s bears a secret but does not override toString()\n", file, start, watched
            inclass = 0
        }
        FNR == 1 { flush(prevfile); prevfile = FILENAME }
        /^[[:space:]]*(abstract[[:space:]]+|sealed[[:space:]]+|final[[:space:]]+|base[[:space:]]+|interface[[:space:]]+|mixin[[:space:]]+)*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/ {
            for (i = 1; i <= NF; i++) if ($i == "class") { cname = $(i + 1); break }
            sub(/[<({].*/, "", cname)
            if (cname ~ /(Credential|Password|Secret|Session|Token)/) {
                inclass = 1; seen = 0; start = FNR; watched = cname
                # The class body brace count STARTS on this line. It used to
                # start at 0 here, because `next` skipped the counting below and
                # the class-opening `{` was therefore never counted — so the
                # first member line holding a balanced `{...}` looked like the
                # class closing, and everything after it was invisible.
                #
                # Measured on real M2 code: `class Credentials {` was declared
                # closed at `const Credentials({required this.username, ...});`
                # on line 13, so the `toString()` on line 38 was never seen and
                # all three secret-bearing classes were reported as violations
                # while every one of them overrode it. A gate that cries wolf
                # teaches people to rename the class, which is precisely the
                # answer §9 does not want.
                line = bare($0)
                depth = gsub(/{/, "{", line) - gsub(/}/, "}", line)
            }
            next
        }
        inclass {
            if ($0 !~ /^[[:space:]]*\/\// &&
                $0 ~ /^[[:space:]]*(@override[[:space:]]+)?String[[:space:]]+toString[[:space:]]*\([[:space:]]*\)/) seen = 1
            line = bare($0)
            depth += gsub(/{/, "{", line) - gsub(/}/, "}", line)
            if (depth <= 0 && index(line, "}") > 0) flush(FILENAME)
        }
        END { flush(prevfile) }
    ' "${files[@]}" || true
}

# SPEC.md §5.1 from the other end. `core_purity` says `filefin_core` must not
# reach the network; this says `apps/*` must not reach it EITHER — not because
# the app is pure, but because `filefin_api` is the only place a `401` is
# interpreted (F3), the only place a certificate is pinned (F15) and the only
# place a cookie jar exists. A widget that opens its own socket bypasses all
# three at once, and every one of them fails silently rather than loudly: the
# request simply succeeds, unauthenticated, unpinned, and against a server
# whose identity nobody checked.
#
# The concrete temptation this exists for is `Image.network` and the poster
# route. That route sits behind `s.auth`, so a raw `HttpClient` fetch of it
# 401s — and the obvious next step is a hand-rolled client with the cookie
# copied into it, which is F15's bypass written by accident. M3 answers it with
# a custom `ImageProvider` fetching through `FileFinClient` instead.
#
# SCOPE IS `apps/*/lib` AND NOTHING ELSE. `filefin_api` cannot satisfy this —
# dio and `HttpClient` are its entire job — and `dart_lib_sources` alone would
# therefore report the layer that is behaving correctly. Tests are out of scope
# too: `test_live/` sets `HttpOverrides.global = null` to get real sockets back
# from `flutter_test`'s binding, which is the right thing to do there.
#
# **THE PATTERN LISTS `Image.network` BECAUSE IT DID NOT, AND THAT WAS THE ONE
# BYPASS THE PARAGRAPH ABOVE NAMES.** Until M3.R the pattern was
# `package:dio/|package:http/|HttpClient\(|HttpOverrides|IOClient`, and
# `Image.network`, `NetworkImage` and `FadeInImage.network` match none of them:
# they build their own `HttpClient` *inside the framework*, so nothing the
# check greps for ever appears in the app's source. Measured on a probe file —
# `check-constitution.sh` said "no new violations", rc 0, and `dart analyze
# --fatal-infos` said "No issues found". The only proof run recorded at M3 was
# `final c = HttpClient();`, which is the one form the old pattern did list.
#
# The comment-line filter is load-bearing, not tidiness:
# `poster_image_provider.dart`'s own doc comments explain *why* `Image.network`
# cannot work here, and without the filter the file documenting the rule
# becomes two violations of it.
#
# **`package:media_kit` is refused everywhere but two named files, and that is
# the same rule rather than a new one.** libmpv opens its own socket from
# NATIVE code, so every reason above applies to it and not one of the patterns
# above can see it: there is no `HttpClient(` to grep for, the request is made
# by C, and it succeeds. The three bypasses are real and each is answered in
# code rather than by hope — the cookie jar (`playbackHeaders()` reads the live
# cookie out and hands it over immediately before the open), F3 (that call is a
# real authenticated round trip, so a dead session is renewed first) and F15
# (it cannot be answered, which is what D10's refusal is for).
#
# Confining the import to two files is what makes those three answers
# reviewable. `media_kit_playback_host.dart` translates our types into
# media_kit's and `mpv_player.dart` wraps the `Player` itself; everything else
# in the app talks to the `PlaybackHost` port and cannot reach libmpv at all.
# The exclusion is built by FILTERING THE ARRAY rather than by `grep -v` on the
# output, because a path filter on grep output matches a path appearing
# anywhere in the line — including inside a string — and would exempt any file
# that merely mentioned the adapter's name.
check_app_no_raw_http() {
    local files=() f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(dart_lib_sources -path 'apps/*')
    if [ ${#files[@]} -eq 0 ]; then return 0; fi
    grep -nHE "package:dio/|package:http/|HttpClient\(|HttpOverrides|IOClient|NetworkImage|Image\.network|FadeInImage\.[a-zA-Z]*[Nn]etwork" "${files[@]}" \
        | grep -vE "^[^:]*:[0-9]+:[[:space:]]*(///|//|\*)" || true

    local outside=()
    for f in "${files[@]}"; do
        case "$f" in
            */lib/src/playback/mpv_player.dart) ;;
            */lib/src/playback/media_kit_playback_host.dart) ;;
            *) outside+=("$f") ;;
        esac
    done
    if [ ${#outside[@]} -eq 0 ]; then return 0; fi
    grep -nHE "package:media_kit" "${outside[@]}" \
        | grep -vE "^[^:]*:[0-9]+:[[:space:]]*(///|//|\*)" || true

    # THE TWO ALLOWED FILES ARE THEMSELVES CHECKED, for the two ways a file
    # that MAY import media_kit can hand it to one that may not — neither of
    # which contains the string above in the receiving file at all:
    #
    #   part 'mpv_part.dart';                        the part uses `Player`
    #                                                with no import line
    #   export 'package:media_kit/media_kit.dart';   any third file importing
    #                                                this one gets `Player`
    #
    # Both were measured to pass silently at M4.R/G6. Both need a one-line
    # change inside an allowed file, so they were always review-visible — but
    # STATE.md's claim that the rest of the app "cannot reach libmpv at all"
    # was enforced for DIRECT imports only, and a claim a gate does not cover
    # is a claim that decays. Neither construct exists anywhere in
    # `apps/mobile/lib` today, so the correct count is zero and any use is new
    # debt that has to be argued for.
    #
    # The allowed list is rebuilt rather than shared with the loop above,
    # because that loop keeps the files it must NOT look at.
    local allowed=()
    for f in "${files[@]}"; do
        case "$f" in
            */lib/src/playback/mpv_player.dart) allowed+=("$f") ;;
            */lib/src/playback/media_kit_playback_host.dart) allowed+=("$f") ;;
        esac
    done
    if [ ${#allowed[@]} -eq 0 ]; then return 0; fi
    grep -nHE "^[[:space:]]*(export|part)[[:space:]]" "${allowed[@]}" || true
}

CHECKS="placeholders core_purity id_typedefs dead_types undocumented_endpoint secret_tostring app_no_raw_http"

# --- ratchet ----------------------------------------------------------------

baseline_for() {
    [ -f "$BASELINE" ] || { echo 0; return; }
    local n
    n=$(awk -v k="$1" '$1 == k { print $2 }' "$BASELINE")
    echo "${n:-0}"
}

if [ "$MODE" = "accept" ]; then
    # CLAUDE.md: the counts "may only ever fall". `accept` used to warn on a
    # rise and then write the raised baseline anyway, exiting 0 — a one-command
    # release valve that legitimised the violation it was warning about. It now
    # REFUSES, and the override is deliberate, named, and has to be said out
    # loud in STATE.md.
    rises=0
    for c in $CHECKS; do
        new=$("check_$c" | grep -c . || true)
        old=$(baseline_for "$c")
        if [ "$new" -gt "$old" ]; then
            echo "ERROR: $c rises $old -> $new — that is new debt, not paid debt."
            rises=1
        fi
    done
    if [ "$rises" -eq 1 ]; then
        if [ "${FILEFIN_ACCEPT_NEW_DEBT:-0}" != "1" ]; then
            fail "constitution-accept will not raise a baseline.
       Fix the new violation. If the debt is a deliberate, stated decision,
       re-run with FILEFIN_ACCEPT_NEW_DEBT=1 and record it in STATE.md's
       'Debt this milestone knowingly accepts' — silence reads as 'there was
       none'."
        fi
        echo "WARNING: FILEFIN_ACCEPT_NEW_DEBT=1 — accepting new debt, not paying it."
    fi
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
