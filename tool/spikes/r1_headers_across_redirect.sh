#!/usr/bin/env bash
# R1 — does the session Cookie survive the 307 redirect to HLS, and onto the
# segment requests? (SPEC.md §5.3, §8 R1)
#
# Why ffmpeg proves something about libmpv: media_kit embeds libmpv, and libmpv
# uses FFmpeg's libavformat for HTTP and HLS. The `http` and `hls` demuxers
# exercised here are the same code that will run inside the app.
#
# The negative control is not decoration. A spike whose command cannot fail
# proves nothing (CLAUDE.md, "Gates must be able to fail"), so TEST 2 repeats
# the fetch with no cookie and the script reports INVALID unless it fails.
#
# Prerequisites: a seeded FileFin server (see tool/testserver/seed.sh) and
# ffmpeg on PATH.
#
# Usage:  FILEFIN_BIN=... FILEFIN_RUN=... tool/spikes/r1_headers_across_redirect.sh
set -uo pipefail

BIN="${FILEFIN_BIN:-$HOME/development/filefin-test/filefin}"
RUN="${FILEFIN_RUN:-$HOME/development/filefin-test/run}"
PORT="${FILEFIN_PORT:-8099}"
USER_NAME="${FILEFIN_USER:-testuser}"
PASS="${FILEFIN_PASS:-TestPassw0rd!23}"
TRANSCODE_CATEGORY="${FILEFIN_TRANSCODE_CATEGORY:-2}"

for tool in ffmpeg curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: $tool not on PATH"; exit 2; }
done
[ -x "$BIN" ] || { echo "FATAL: filefin binary not found at $BIN"; exit 2; }

export HOME="$RUN/home"
B="http://127.0.0.1:$PORT"
C="$RUN/cookies-r1"

"$BIN" serve > "$RUN/server-r1.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

curl -fsS -c "$C" -X POST "$B/api/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\"}" >/dev/null || {
  echo "FATAL: login failed — is the server seeded?"; exit 2; }
SESSION=$(awk '/filefin_session/{print $7}' "$C")

# A transcode-only item: requesting its file/0 must 307 to HLS.
TRANS=$(curl -fsS -b "$C" "$B/api/category/$TRANSCODE_CATEGORY/media" \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
[ -n "$TRANS" ] || { echo "FATAL: no media in category $TRANSCODE_CATEGORY"; exit 2; }
URL="$B/api/media/$TRANS/file/0"

echo "== TEST 1: with cookie (expect success) =="
ffmpeg -nostdin -loglevel warning \
  -headers $'Cookie: filefin_session='"$SESSION"$'\r\n' \
  -i "$URL" -t 2 -f null - 2>&1 | tail -15
RC1=${PIPESTATUS[0]}; echo "exit=$RC1"

echo "== TEST 2: negative control, no cookie (MUST fail) =="
ffmpeg -nostdin -loglevel warning -i "$URL" -t 2 -f null - 2>&1 | tail -5
RC2=${PIPESTATUS[0]}; echo "exit=$RC2"

echo "== TEST 3: byte-level segment fetch =="
curl -sS -b "$C" -o /dev/null -D - "$URL/hls/index.m3u8" | grep -Ei '^HTTP'
curl -sS -b "$C" -o /dev/null -D - "$URL/hls/seg0.ts" | grep -Ei '^(HTTP|Content-Type|Content-Length)'

if [ "$RC1" -eq 0 ] && [ "$RC2" -ne 0 ]; then
  echo "R1: PASS — cookie survives the redirect; control failed as required."
  exit 0
elif [ "$RC1" -eq 0 ]; then
  echo "R1: INVALID — control also succeeded; the endpoint is not gated."
  exit 1
else
  echo "R1: FAIL — cookie did not survive; the HLS path needs a different design."
  exit 1
fi
