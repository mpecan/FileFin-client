#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Verify the captured fixtures (CLAUDE.md §8).
#
# Two independent checks, because they catch different lies:
#
#   1. SHA-256 manifest. A fixture is a record of what a real server said. The
#      failure mode this guards is editing one so a failing test passes, which
#      converts "captured real payload" back into "a literal that agrees with
#      our own class" — precisely what §8 exists to prevent. A legitimate
#      re-capture regenerates the manifest, so the edit shows up in review as a
#      manifest diff next to a documented reason.
#
#   2. Structural assertions. A checksum cannot tell a rich payload from a
#      degenerate one, so this half asserts the fixture set still exercises the
#      shapes the models depend on: populated rich fields, a two-file item, a
#      non-zero resume pointer, both playback branches.
#
#   3. A key-set ratchet (KEYS.txt). The named assertions in (2) cover about
#      fifteen fields; the payloads carry hundreds. Deleting eight top-level and
#      five per-file keys and then re-running `accept` used to leave a gutted
#      payload passing both halves, because `accept` regenerated the only thing
#      that would have noticed. KEYS.txt records every JSON path ever captured
#      and behaves like the constitution ratchet: `accept` may ADD keys (§8 says
#      a server upgrade that adds a field must not break us) and REFUSES to drop
#      one.
#
# Usage: tool/check-fixtures.sh [verify|accept]

DIR="test/fixtures"
MANIFEST="$DIR/SHA256SUMS"
KEYS="$DIR/KEYS.txt"
MODE="${1:-verify}"

[ -d "$DIR" ] || fail "$DIR does not exist — run 'just fixtures-seed && just fixtures-capture'"
command -v jq >/dev/null 2>&1 || fail "jq not on PATH — the structural half of this gate cannot run"

# PROVENANCE.md is IN the manifest. It was excluded, so nothing tied the record
# of how a fixture was produced to the bytes it describes: a re-capture could
# change every payload and leave the provenance table untouched and unchecksummed.
# Only SHA256SUMS itself is exempt, because it cannot contain its own hash.
hash_all() {
    (cd "$DIR" && find . -type f -not -name SHA256SUMS \
        | sed 's|^\./||' | sort | while IFS= read -r f; do
            printf '%s  %s\n' "$(shasum -a 256 "$f" | awk '{print $1}')" "$f"
        done)
}

# Every JSON path in every JSON fixture, as `<file><TAB><path>`. Array indices
# collapse to `[]` so adding a third media item is not a key change, but
# dropping `files[].subtitles` is.
keys_all() {
    (cd "$DIR" && find . -name '*.json' -not -name SHA256SUMS | sed 's|^\./||' | sort \
        | while IFS= read -r f; do
            jq -r 'paths | map(if type == "number" then "[]" else tostring end) | join(".")' "$f" \
                | sort -u | sed "s|^|$f\t|"
        done)
}

if [ "$MODE" = "accept" ]; then
    current_keys="$(mktemp)"
    trap 'rm -f "$current_keys"' EXIT
    keys_all > "$current_keys"

    if [ -f "$KEYS" ]; then
        lost="$(comm -23 <(sort "$KEYS") <(sort "$current_keys"))"
        if [ -n "$lost" ]; then
            echo "$lost" | sed 's/^/  -/'
            if [ "${FILEFIN_ACCEPT_FIXTURE_KEY_LOSS:-0}" != "1" ]; then
                fail "the re-captured fixtures have LOST the keys above.
       That is either upstream removing a field — in which case docs/server-api.md
       and the affected model change in the same commit (§8) — or a payload that
       was edited rather than captured. Re-run with
       FILEFIN_ACCEPT_FIXTURE_KEY_LOSS=1 once you know which, and say so in the
       commit message."
            fi
            echo "WARNING: FILEFIN_ACCEPT_FIXTURE_KEY_LOSS=1 — recording the loss."
        fi
    fi

    cp "$current_keys" "$KEYS"
    hash_all > "$MANIFEST"
    echo "fixtures: wrote $(grep -c . "$KEYS") key paths to $KEYS"
    echo "fixtures: wrote $(grep -c . "$MANIFEST") checksums to $MANIFEST"
    exit 0
fi

[ -f "$MANIFEST" ] || fail "$MANIFEST is missing — run 'bash tool/check-fixtures.sh accept' after a capture"

current="$(mktemp)"
trap 'rm -f "$current"' EXIT
hash_all > "$current"

if ! diff -u "$MANIFEST" "$current"; then
    fail "a fixture's bytes do not match the committed manifest.
       If you re-captured against a real server, regenerate with
       'bash tool/check-fixtures.sh accept' and say in the commit which
       upstream version it came from (§8). If you did not, a fixture was
       edited by hand — put it back."
fi

# --- structural assertions --------------------------------------------------
# Each names what would be silently lost if it stopped holding.

[ -f "$KEYS" ] || fail "$KEYS is missing — run 'bash tool/check-fixtures.sh accept' after a capture"

missing_keys="$(comm -23 <(sort "$KEYS") <(keys_all | sort))"
if [ -n "$missing_keys" ]; then
    echo "$missing_keys" | sed 's/^/  -/'
    fail "$(printf '%s' "$missing_keys" | grep -c .) captured JSON key path(s) are gone.
       The checksum half above already passed, so the manifest was regenerated —
       which means a payload was edited and re-accepted, not re-captured. Put it
       back, or if upstream really dropped the field, change the doc and the
       model with it (§8)."
fi

need() {
    local file="$1" filter="$2" what="$3"
    [ -f "$DIR/$file" ] || fail "$DIR/$file is missing"
    jq -e "$filter" "$DIR/$file" >/dev/null 2>&1 || fail "$file: $what"
}

need media_detail_directplay.json '(.metadata | length) > 0' \
    "metadata is empty; a decoder that drops it would still round-trip"
need media_detail_directplay.json '(.ratings | length) > 0' "ratings is empty"
need media_detail_directplay.json '(.technical | length) > 0' "technical is empty"
need media_detail_directplay.json '(.actors | length) > 0' "actors is empty"
need media_detail_directplay.json '(.genres | length) > 0' "genres is empty"
need media_detail_directplay.json '(.tags | length) > 0' \
    "tags is empty — meta.json's version must be importer.MetaVersion or upgradeMeta nils it"
need media_detail_directplay.json '.files[0].transcode == false' \
    "the direct-play item must report transcode=false; without it only one playback branch is covered"
need media_detail_directplay.json '(.files[0].subtitles | length) > 0' \
    "no sidecar subtitle; SubtitleInfo would decode against an empty list"
need media_detail_directplay.json '.files[0].season == 0 and .files[0].episode == 0' \
    "the single-file item must have season/episode 0 — that is the empty-ref half of state.Refs"

need media_detail_multifile_advanced.json '(.files | length) == 2' \
    "the multi-file item lost its second file"
need media_detail_multifile_advanced.json '.files[1].episode == 2' \
    "the SxE parse did not take; season/episode would be untested"
need media_detail_multifile_advanced.json '.continueIndex == 1' \
    "the resume pointer is not on file 1 — the 90%-crossing advance is uncovered"
need media_detail_multifile_advanced.json '.files[0].transcode == true' \
    "the HEVC item must report transcode=true; without it the HLS branch is uncovered"

need search_results.json 'length > 0' "search_results.json has no results in it"
need home_populated.json '(.continue | length) > 0' "the continue row is empty"
need home_populated.json 'has("favorites") and has("completed")' "a home row key is missing"
need categories.json 'length >= 2 and (.[0].id | type) == "number"' \
    "categories must be a list with a numeric id (CategoryId is an int64, CLAUDE.md §7)"
# The nesting assertions. `GET /api/categories` is flat and the client builds
# the tree (SPEC.md §3.2), so a capture with no non-zero parentId would leave
# `buildCategoryTree`'s entire subject proven against fabricated rows only —
# which is what CLAUDE.md §8 says a hand-written literal is worth.
need categories.json 'any(.[]; .parentId != 0)' \
    "no category has a non-zero parentId, so nesting is captured nowhere. Re-seed:
       tool/testserver/seed.sh writes Films/Documentaries/config.json for this"
need categories.json 'any(.[]; .name != .leaf)' \
    "no category has a name that differs from its leaf. \`name\` is the FULL PATH and
       \`leaf\` is the display name; a tree rendering the wrong one prints
       \"Films/Documentaries\" on every nested row, and only a nested capture shows it"
need categories.json 'any(.[]; .media == 0 and .empty == true)' \
    "no empty category. A listing whose counts are 0 is what the UI must not read as
       \"empty library\" — library.go:73-81 returns 0 for both when the cache is down"
need media_detail_directplay.json '(.id | type) == "string"' \
    "media id must be a string (MediaId is a 12-char hex string, CLAUDE.md §7)"
need search_empty.json 'length == 0' "the empty-search fixture is not empty"
# BOTH poster answers must be captured. Before M3.3 every item said
# `hasPoster:false`, so a decoder or a UI that never handled `true` looked
# perfectly healthy — and the poster route's 200 branch was covered nowhere.
need category_media.json 'any(.[]; .hasPoster == true)' \
    "no item has a poster; seed.sh copies tool/testserver/poster.jpg into the film"
need media_detail_multifile_advanced.json '.hasPoster == false' \
    "the show must have NO poster, so the 404-means-no-poster branch stays covered"
need tags.json 'length > 0' "the tag vocabulary is empty"

# resume_vectors.json — the M1.7 differential oracle. It is not an HTTP capture
# (tool/capture-resume-vectors.sh runs the upstream engine directly), and it was
# for a while the one fixture backed by the checksum alone: a truncated file
# passed `fixtures-verify` as soon as the manifest was regenerated.
need resume_vectors.json '(.vectors | length) > 500' \
    "the vector grid did not run in full — the oracle would silently narrow"
need resume_vectors.json '.watchedThreshold == 0.90' \
    "WatchedThreshold is not 0.90; the whole crossing rule is captured against it"
need resume_vectors.json '[.vectors[].in.refs] | map(
        if length == 1 and .[0] == "" then "single"
        elif any(.[]; startswith("#")) then "hash"
        else "sxe" end) | unique | length == 3' \
    "the vectors do not cover all three Refs branches (\"\", \"SxE\", \"#N\") — state/engine.go:17"
need resume_vectors.json '[.vectors[] | . as $v | select(
        $v.out.pointer != null
        and ($v.in.refs | index($v.out.pointer.file)) == null
    )] | length > 0' \
    "no vector has an output pointer whose ref is absent from refs. That is the
       case where View reports continueIndex/continueSeconds 0 with a non-nil
       pointer, and it is the only thing that distinguishes a correct View from
       'pointer?.seconds ?? 0' — which passed all 333 of the previous vectors"
need resume_vectors.json '[.vectors[] | select(
        .out.pointer != null
        and .out.pointer.seconds != 0
        and .out.view.continueSeconds == 0
    )] | length > 0' \
    "no vector pins continueSeconds to 0 while the stored pointer holds seconds"

for f in error_shapes.txt hls_index.m3u8 subtitle.vtt PROVENANCE.md; do
    [ -s "$DIR/$f" ] || fail "$DIR/$f is missing or empty"
done
grep -q '^#EXT-X-ENDLIST' "$DIR/hls_index.m3u8" || \
    fail "hls_index.m3u8 has no #EXT-X-ENDLIST — the VOD playlist shape SPEC §3.4 describes is not captured"
grep -q 'HTTP 415' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 415 — F12's message has nothing to be written against"
grep -q '^Location:.*hls/index.m3u8' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 307 Location to the HLS playlist"
# BOTH 415s, and they are different sentences from different routes (SPEC §3.4).
# The file route's `transcoding disabled` is the only one a client can receive,
# because `PlaybackRequest.url` is always the file route and libmpv follows the
# 307 itself; the hls route's `not transcodable` is the symmetric half. Keeping
# both captured is what stops a maintainer "fixing" F12's message to cover a
# case that cannot reach it.
#
# `-x`, and that is not pedantry: for THREE of the five strings anchored in this
# section the capture writes a COMMENT above the block naming the same words, so
# an unanchored grep passed against a file whose payload line had been deleted —
# measured while proving this gate in both directions. (`HTTP 415` and the
# `Location:` line are not shadowed by their own comments; they are anchored for
# consistency and cost nothing.) An assertion satisfiable by prose is one
# CLAUDE.md names by name.
grep -qx 'transcoding disabled' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 'transcoding disabled' — that is the FILE route's
       415 and the only one this client can see. It needs a server with
       transcodeEnabled off; capture_fixtures.sh does that and puts it back"
grep -qx 'not transcodable' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 'not transcodable' — the HLS route's 415, the
       symmetric half of SPEC §3.4"

# THE OTHER FIVE BLOCKS. Until M5.R this gate guarded four of about twelve, and
# the rest were guarded only inside `capture_fixtures.sh` — which needs a real
# server, is not in `just check` and cannot run in CI. A hand-edit followed by
# `fixtures-accept` therefore laundered them away with `verify` still exit 0,
# which is the exact attack the structural half exists to stop (proven at M4
# with `jq '.tags = []'`). Anchored for the reason above.
grep -qx 'bad file index' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 'bad file index' — the 400 the progress route
       answers when an item's file list changed under us. It is what
       ProgressReporter turns into ReportStop.rejected, and the only capture of it"
grep -qx 'rating out of range' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 'rating out of range' — the OTHER 400 body, and
       the one that shows BadRequest carries a route-specific sentence rather
       than a single fixed string"
grep -qx 'WEBVTT' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no WEBVTT line — the sidecar route converts SRT to
       WebVTT on the fly (SPEC §3.4), and subtitleText's whole contract is that
       what comes back is already WebVTT"
grep -qE '^Content-Range: bytes 0-49/[0-9]+$' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 206 Content-Range header — byte-range serving on
       the direct-play route is F8's foundation and this is its only capture"
grep -qE '^(401 )+(429 )+$' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 401…429 rate-limit sequence — the lockout that
       RateLimited and Retry-After are written against"
# A GATE AGAINST ONE SPECIFIC FALSEHOOD COMING BACK. The last block of this file
# used to read "the browser-native verdict is decided by EXTENSION, not by probed
# codecs" — the unprobed fallback read as the rule. It was retracted in four
# other documents at M4 and left standing here, in a CAPTURED FIXTURE, which §8
# treats as evidence. It is evidence for something untrue.
# `-i`, and a wider alternation than the retracted sentence used. A tripwire on
# one exact spelling is defeated by re-typing the claim: `decided by the
# EXTENSION`, `decided by extension` and `decided by the file suffix` all sailed
# through the case-sensitive literal (M5.R/G-F3). Case-insensitivity costs
# nothing, and the real defence is still the SHA-256 manifest forcing any edit
# through `fixtures-accept` into a reviewable diff.
if grep -qiE 'decided by (the )?(file )?(extension|suffix)' "$DIR/error_shapes.txt"; then
    fail "error_shapes.txt states the RETRACTED claim that the browser-native
       verdict is decided by the file extension. It is decided by the PROBED
       container and codecs when the cache row has them (playback.go:78), and
       falls back to the extension only when it does not — which is every row
       in the seeded library, because seed.sh never probes. See CLAUDE.md
       'Playback truths' and tool/spikes/e5_mkv_direct_play.sh."
fi

echo "fixtures: $(grep -c . "$MANIFEST") file(s) match the manifest, $(grep -c . "$KEYS") captured key path(s) are intact, and all structural assertions hold"
