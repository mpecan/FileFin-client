#!/usr/bin/env bash
# Captures REAL response payloads from a seeded FileFin server into
# test/fixtures/, which every model round-trips in its tests (CLAUDE.md §8).
#
# Why this script exists rather than hand-written JSON: a literal we author
# ourselves only proves we can spell our own field names. It cannot catch a
# field the server spells differently, a number that arrives as a string, or a
# rounding rule we did not know about — this capture found continueSeconds
# returning 2 for a reported position of 1.5.
#
# Run tool/testserver/seed.sh first. Re-running is safe and overwrites.
#
# Usage: tool/testserver/capture_fixtures.sh
set -euo pipefail

BIN="${FILEFIN_BIN:-$HOME/development/filefin-test/filefin}"
RUN="${FILEFIN_RUN:-$HOME/development/filefin-test/run}"
PORT="${FILEFIN_PORT:-8099}"
USER_NAME="${FILEFIN_USER:-testuser}"
PASS="${FILEFIN_PASS:-TestPassw0rd!23}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$REPO/test/fixtures"

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl not on PATH"; exit 2; }
[ -x "$BIN" ] || { echo "FATAL: filefin binary not found at $BIN"; exit 2; }
[ -d "$RUN/data" ] || { echo "FATAL: no seeded data; run tool/testserver/seed.sh"; exit 2; }

export HOME="$RUN/home"
B="http://127.0.0.1:$PORT"
C="$RUN/cookies-capture"
CFG="$RUN/home/.filefin.json"
CFG_BAK="$RUN/home/.filefin.json.capture-bak"
CFG_PRISTINE="$RUN/home/.filefin.json.capture-pristine"
mkdir -p "$OUT"

# The 415 block below needs `transcodeEnabled: false`, which is a CONFIG key
# rather than a request parameter, so this script edits the seeded config and
# has to put it back. A `transcodeEnabled: false` left in $RUN turns
# integration_test/playback_test.dart's 307 assertion red on unmodified code —
# M4.R/T1 with a different key — so the restore is a trap rather than a line at
# the end, and the script FAILS if the config does not come back byte-identical.
#
# What is compared at the end is the `transcodeEnabled` LINE, not the whole
# file: the server rewrites `lastLoginAt` on every login and this script logs
# in, so a byte comparison fails for a reason that has nothing to do with the
# key. Measured on the first run of this code.
cp "$CFG" "$CFG_PRISTINE"
TRANSCODE_LINE="$(grep '"transcodeEnabled"' "$CFG")"
SRV=
cleanup() {
  [ -n "$SRV" ] && kill "$SRV" 2>/dev/null
  [ -f "$CFG_BAK" ] && mv -f "$CFG_BAK" "$CFG"
  rm -f "$CFG_PRISTINE"
  return 0
}
trap cleanup EXIT INT TERM

start_server() {
  "$BIN" serve > "$RUN/capture-server.log" 2>&1 &
  SRV=$!
  for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && return 0; sleep 0.25; done
  echo "FATAL: the server did not become ready"; exit 1
}
stop_server() {
  [ -n "$SRV" ] || return 0
  kill "$SRV" 2>/dev/null || true
  wait "$SRV" 2>/dev/null || true
  SRV=
}

start_server

get()  { curl -fsS -b "$C" "$B$1"; }
save() { echo "  $1"; cat > "$OUT/$1"; }
post() { curl -fsS -b "$C" -X POST "$B$1" -H 'Content-Type: application/json' -d "$2" -o /dev/null -w "%{http_code}"; }

curl -fsS "$B/api/state" | save state.json
curl -fsS -c "$C" -X POST "$B/api/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\"}" | save login.json

get /api/me         | save me.json
get /api/categories | save categories.json
get /api/tags       | save tags.json

DIRECT=$(get "/api/category/1/media" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
TRANS=$(get  "/api/category/2/media" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
[ -n "$DIRECT" ] && [ -n "$TRANS" ] || { echo "FATAL: could not resolve both media items"; exit 1; }

# RESET the per-user state FIRST, so the two payloads below really are the
# ones with nothing on them.
#
# `meta.json` is filesystem truth and survives everything (`state/state.go`),
# so the POSTs further down leave a favourite, a rating and a resume pointer
# behind — and the NEXT run of this script captures them into
# `media_detail_directplay.json`, whose entire job is to be the payload with no
# state. Measured on the second consecutive run: `favorite:false rating:0
# continueSeconds:0` became `true / 8 / 2`, and `media_detail_transcode.json`
# picked up `watched:true` and `continueIndex:1`. That is the same
# non-idempotence M4.R had to fix in `FixtureRun._decorrelateWatched`, in a
# second place. DELETE .../watched clears the flag AND nils the pointer
# (`media.go:485`), which is what makes it the right one of the two.
del() { curl -fsS -b "$C" -X DELETE "$B$1" -o /dev/null -w "%{http_code}"; }
for id in "$DIRECT" "$TRANS"; do
  del "/api/media/$id/watched"   >/dev/null
  del "/api/media/$id/progress"  >/dev/null
  post "/api/media/$id/favorite" '{"favorite":false}' >/dev/null
  post "/api/media/$id/rating"   '{"rating":0}'       >/dev/null
done

get "/api/category/1/media" | save category_media.json
get "/api/media/$DIRECT"    | save media_detail_directplay.json
get "/api/media/$TRANS"     | save media_detail_transcode.json

# Drive per-user state so the home rows and the resume fields are non-empty.
# An all-empty fixture would let a decoder that drops these fields still pass.
post "/api/media/$DIRECT/favorite" '{"favorite":true}' >/dev/null
post "/api/media/$DIRECT/rating"   '{"rating":8}'      >/dev/null
post "/api/media/$DIRECT/progress" '{"file":0,"position":1.5,"duration":3.0,"event":"timeupdate"}' >/dev/null
post "/api/media/$TRANS/watched"   '{"watched":true}'  >/dev/null

# Cross 90% of the show's FIRST of two files. engine.go:65-71 advances the
# pointer to (file+1, 0s) rather than leaving it at 96% of file 0, and this is
# the only fixture in the set where continueIndex is non-zero — M1's resume
# engine has to reproduce exactly this.
post "/api/media/$TRANS/progress" '{"file":0,"position":2.9,"duration":3.0,"event":"timeupdate"}' >/dev/null

get /api/home                          | save home_populated.json
get "/api/media/$DIRECT"               | save media_detail_with_state.json
get "/api/media/$TRANS"                | save media_detail_multifile_advanced.json
get "/api/search?q=Movie&field=all"    | save search_results.json
get "/api/search?q=zzzznope&field=all" | save search_empty.json
get "/api/media/$TRANS/file/0/hls/index.m3u8" | save hls_index.m3u8
get "/api/media/$DIRECT/file/0/sub/0"         | save subtitle.vtt

# The poster BYTES. docs/server-api.md carried "No fixture" here until M3.3, on
# the grounds that the seeded items had no poster and a blob decodes into no
# model. The first half stopped being true when seed.sh started copying one in;
# the second half is answered by what this fixture actually asserts — not a
# decode, but that `http.ServeFile` hands back the seeded bytes UNCHANGED. That
# is reproducible precisely because the seed input is a committed file rather
# than a fresh encode.
get "/api/media/$DIRECT/poster" | save poster.jpg

# Error and header shapes. These are contract too: F12 promises to explain a
# 415 in the user's terms, and F3 keys off the 401.
{
  echo "# 401 unauthenticated GET /api/me"
  curl -sS "$B/api/me" -o - -w '\nHTTP %{http_code}\n'
  echo
  echo "# 404 unknown media id"
  curl -sS -b "$C" "$B/api/media/deadbeefdead" -o - -w '\nHTTP %{http_code}\n'
  echo
  echo "# 307 raw bytes refused for a transcode-only file (SPEC 3.4)"
  curl -sS -b "$C" -o /dev/null -D - "$B/api/media/$TRANS/file/0" | grep -Ei '^(HTTP|Location)'
  echo
  echo "# 415 HLS refused for a direct-playable file (SPEC 3.4, the symmetric half)"
  curl -sS -b "$C" "$B/api/media/$DIRECT/file/0/hls/index.m3u8" -o - -w '\nHTTP %{http_code}\n'
  echo
  echo "# 206 byte range on the direct-play file"
  curl -sS -b "$C" -r 0-49 -o /dev/null -D - "$B/api/media/$DIRECT/file/0" \
    | grep -Ei '^(HTTP|Content-Range|Content-Length|Accept-Ranges|Content-Type)'
  echo
  echo "# 400 bad file index: POST /api/media/{id}/progress with file: 99"
  curl -sS -b "$C" -X POST "$B/api/media/$TRANS/progress" \
    -H 'Content-Type: application/json' \
    -d '{"file":99,"position":1,"duration":10,"event":"stop"}' \
    -o - -w '\nHTTP %{http_code}\n'
  echo
  echo "# 400 rating out of range: POST /api/media/{id}/rating with {\"rating\": 99}"
  curl -sS -b "$C" -X POST "$B/api/media/$DIRECT/rating" \
    -H 'Content-Type: application/json' -d '{"rating":99}' \
    -o - -w '\nHTTP %{http_code}\n'
  echo
  echo "# 200 the sidecar subtitle route, converted SRT -> WebVTT per request"
  curl -sS -b "$C" -D - "$B/api/media/$DIRECT/file/0/sub/0" | grep -Ev '^(Content-Security|Permissions|Referrer|X-|Date|Content-Length)'
  echo
  echo "# login rate limiting: 8 bad passwords in a row"
  for _ in $(seq 1 8); do
    curl -sS -X POST "$B/api/login" -H 'Content-Type: application/json' \
      -d '{"username":"testuser","password":"wrong"}' -o /dev/null -w '%{http_code} '
  done
  echo
} 2>&1 | tr -d '\r' > "$OUT/error_shapes.txt"

# The 415 A CLIENT CAN ACTUALLY RECEIVE, and it is not the one that was already
# captured. The hls route's `415 not transcodable` above is the symmetric half
# of SPEC §3.4 and is unreachable from this client, because `PlaybackRequest.url`
# is always the FILE route and libmpv follows the 307 itself. F12's 415 is the
# file route's, it says `transcoding disabled`, and it exists only on a server
# whose `transcodeEnabled` is off — so the server is stopped, the key is
# rewritten, and both are put back by the EXIT trap whatever happens.
stop_server
cp "$CFG" "$CFG_BAK"
sed -E 's/"transcodeEnabled"[[:space:]]*:[[:space:]]*[^,}]*/"transcodeEnabled": false/' "$CFG_BAK" > "$CFG"
grep -q '"transcodeEnabled": false' "$CFG" || {
  echo "FATAL: could not switch transcoding off in $CFG — the key has moved or changed shape"; exit 1; }
start_server
# A NEW LOGIN, because the restart killed the session. Server sessions are
# in-memory and die with the process (SPEC.md L1) — without this every request
# below answers 401 and the block captures nothing but the auth middleware.
C2="$RUN/cookies-capture-415"
curl -fsS -c "$C2" -X POST "$B/api/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\"}" -o /dev/null
{
  echo
  echo "# 415 the FILE route on a server with transcoding disabled - F12's own."
  echo "# transcodeEnabled: false. The hls route's 415 above is the OTHER one,"
  echo "# and it is the one this client can never see (SPEC 3.4)."
  curl -sS -b "$C2" "$B/api/media/$TRANS/file/0" -o - -w '\nHTTP %{http_code}\n'
  echo
  echo "# ...and the detail STILL reports transcode:true on that same server,"
  echo "# which is what keeps the client-side guard firing."
  curl -sS -b "$C2" "$B/api/media/$TRANS" \
    | sed -n 's/.*"index":0[^}]*\("transcode":[a-z]*\).*/  file 0: \1/p'
  echo
  echo "# ...while the direct-play film is unaffected"
  curl -sS -b "$C2" -o /dev/null -D - "$B/api/media/$DIRECT/file/0" \
    | grep -Ei '^(HTTP|Accept-Ranges|Content-Type)'
} 2>&1 | tr -d '\r' >> "$OUT/error_shapes.txt"
rm -f "$C2"
stop_server
mv -f "$CFG_BAK" "$CFG"
grep -qF "$TRANSCODE_LINE" "$CFG" || {
  echo "FATAL: $CFG was not restored. Put transcodeEnabled back from $CFG_PRISTINE"
  echo "       before running just it — a stray false turns the 307 test red."
  exit 1; }
start_server

# Guard: a fixture set that is silently empty is worse than none, because the
# round-trip tests would pass against nothing.
for f in state.json login.json me.json categories.json category_media.json \
         media_detail_directplay.json media_detail_transcode.json \
         media_detail_with_state.json media_detail_multifile_advanced.json \
         home_populated.json search_results.json search_empty.json tags.json \
         hls_index.m3u8 subtitle.vtt error_shapes.txt; do
  [ -s "$OUT/$f" ] || { echo "FATAL: fixture $f is empty or missing"; exit 1; }
done
grep -q '"continue":\[{' "$OUT/home_populated.json" || {
  echo "FATAL: home_populated.json has an empty continue row; state did not apply"; exit 1; }

# The rich fields are the reason M0 enriched the seed. An all-empty fixture
# lets a decoder that silently drops metadata/ratings/technical/actors round-trip
# perfectly, so assert each one arrived non-empty before committing anything.
for key in metadata ratings technical actors genres tags; do
  grep -q "\"$key\":\[{\?\"" "$OUT/media_detail_directplay.json" || {
    echo "FATAL: media_detail_directplay.json has an empty '$key' — the fixture would prove nothing"; exit 1; }
done
grep -q '"continueIndex":1' "$OUT/media_detail_multifile_advanced.json" || {
  echo "FATAL: the 90% crossing did not advance the pointer to file 1"; exit 1; }

# The four blocks that used to be HAND-APPENDED to error_shapes.txt, asserted
# here because this script rewrites that file WHOLESALE: a re-capture silently
# deleted three real ones and kept a fourth that stated a retracted claim.
# `-x`: each of these words also appears in the COMMENT above its block, so an
# unanchored match passes against a file whose payload line is gone.
for shape in 'bad file index' 'rating out of range' 'WEBVTT' 'transcoding disabled'; do
  grep -qx "$shape" "$OUT/error_shapes.txt" || {
    echo "FATAL: error_shapes.txt lost the '$shape' block"; exit 1; }
done
# `-i` and an alternation, matching `check-fixtures.sh`: a tripwire on one exact
# spelling is defeated by re-typing the claim (M5.R/G-F3).
grep -qiE 'decided by (the )?(file )?(extension|suffix)' "$OUT/error_shapes.txt" && {
  echo "FATAL: the retracted 'decided by the extension' claim is back in error_shapes.txt"; exit 1; }

# NO CARRIAGE RETURNS. `curl -D -` emits real HTTP headers, which end CRLF, and
# `git config core.autocrlf=input` strips them ON COMMIT — so a manifest
# accepted from a just-captured working tree would not match a fresh clone, and
# `fixtures-verify` would go red in CI for a reason nobody could reproduce
# locally. Measured: HEAD's committed error_shapes.txt carries 0 CRs and a
# freshly captured one carried 13.
! grep -q "$(printf '\r')" "$OUT/error_shapes.txt" || {
  echo "FATAL: error_shapes.txt contains CR bytes; git would strip them on commit"; exit 1; }

# The "no state" payloads really have none. Without this the reset above could
# silently stop working and the next capture would quietly fold state into them.
grep -q '"favorite":false' "$OUT/media_detail_directplay.json" || {
  echo "FATAL: media_detail_directplay.json carries a favourite; the state reset did not run"; exit 1; }
grep -q '"continueIndex":0' "$OUT/media_detail_transcode.json" || {
  echo "FATAL: media_detail_transcode.json carries a resume pointer; the state reset did not run"; exit 1; }
grep -qF "$TRANSCODE_LINE" "$CFG" || {
  echo "FATAL: $CFG no longer carries the transcodeEnabled it started with"; exit 1; }

echo "captured $(ls -1 "$OUT" | wc -l | tr -d ' ') fixtures into test/fixtures/"
