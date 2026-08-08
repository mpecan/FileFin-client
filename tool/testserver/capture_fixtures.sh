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
mkdir -p "$OUT"

"$BIN" serve > "$RUN/capture-server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

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
  echo "# login rate limiting: 8 bad passwords in a row"
  for _ in $(seq 1 8); do
    curl -sS -X POST "$B/api/login" -H 'Content-Type: application/json' \
      -d '{"username":"testuser","password":"wrong"}' -o /dev/null -w '%{http_code} '
  done
  echo
} > "$OUT/error_shapes.txt" 2>&1

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

echo "captured $(ls -1 "$OUT" | wc -l | tr -d ' ') fixtures into test/fixtures/"
