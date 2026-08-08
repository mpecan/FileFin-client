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
# Usage: tool/check-fixtures.sh [verify|accept]

DIR="test/fixtures"
MANIFEST="$DIR/SHA256SUMS"
MODE="${1:-verify}"

[ -d "$DIR" ] || fail "$DIR does not exist — run 'just fixtures-seed && just fixtures-capture'"

hash_all() {
    (cd "$DIR" && find . -type f -not -name SHA256SUMS -not -name PROVENANCE.md \
        | sed 's|^\./||' | sort | while IFS= read -r f; do
            printf '%s  %s\n' "$(shasum -a 256 "$f" | awk '{print $1}')" "$f"
        done)
}

if [ "$MODE" = "accept" ]; then
    hash_all > "$MANIFEST"
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

need() {
    local file="$1" filter="$2" what="$3"
    [ -f "$DIR/$file" ] || fail "$DIR/$file is missing"
    jq -e "$filter" "$DIR/$file" >/dev/null 2>&1 || fail "$file: $what"
}

command -v jq >/dev/null 2>&1 || fail "jq not on PATH — the structural half of this gate cannot run"

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

need home_populated.json '(.continue | length) > 0' "the continue row is empty"
need home_populated.json 'has("favorites") and has("completed")' "a home row key is missing"
need categories.json 'length >= 2 and (.[0].id | type) == "number"' \
    "categories must be a list with a numeric id (CategoryId is an int64, CLAUDE.md §7)"
need media_detail_directplay.json '(.id | type) == "string"' \
    "media id must be a string (MediaId is a 12-char hex string, CLAUDE.md §7)"
need search_empty.json 'length == 0' "the empty-search fixture is not empty"
need tags.json 'length > 0' "the tag vocabulary is empty"

for f in error_shapes.txt hls_index.m3u8 subtitle.vtt PROVENANCE.md; do
    [ -s "$DIR/$f" ] || fail "$DIR/$f is missing or empty"
done
grep -q '^#EXT-X-ENDLIST' "$DIR/hls_index.m3u8" || \
    fail "hls_index.m3u8 has no #EXT-X-ENDLIST — the VOD playlist shape SPEC §3.4 describes is not captured"
grep -q 'HTTP 415' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 415 — F12's message has nothing to be written against"
grep -q '^Location:.*hls/index.m3u8' "$DIR/error_shapes.txt" || \
    fail "error_shapes.txt has no 307 Location to the HLS playlist"

echo "fixtures: $(grep -c . "$MANIFEST") file(s) match the manifest and all structural assertions hold"
