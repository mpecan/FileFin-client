#!/usr/bin/env bash
# Seeds a real FileFin server for integration tests and fixture capture.
#
# Builds a library that exercises BOTH playback branches, because the whole
# playback design turns on the difference (SPEC.md §3.4):
#
#   Films/  (2020) Direct Play Movie.mp4   H.264 + AAC  -> served as raw bytes
#   Shows/  (2019) Transcode Show - 1x1.mkv HEVC + AAC  -> 307 redirect to HLS
#
# A sidecar .srt rides along so the subtitle endpoint has something to convert.
#
# Idempotent: wipes and rebuilds the run directory each time. Leaves an
# installed, cache-populated server that is NOT running; callers start it.
#
# Usage: tool/testserver/seed.sh
# Env:   FILEFIN_BIN, FILEFIN_RUN, FILEFIN_PORT, FILEFIN_USER, FILEFIN_PASS
set -euo pipefail

BIN="${FILEFIN_BIN:-$HOME/development/filefin-test/filefin}"
RUN="${FILEFIN_RUN:-$HOME/development/filefin-test/run}"
PORT="${FILEFIN_PORT:-8099}"
USER_NAME="${FILEFIN_USER:-testuser}"
PASS="${FILEFIN_PASS:-TestPassw0rd!23}"

for tool in ffmpeg curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: $tool not on PATH"; exit 2; }
done
[ -x "$BIN" ] || {
  echo "FATAL: filefin binary not found at $BIN"
  echo "Build it: git clone https://github.com/xuedi/FileFin && cd FileFin \\"
  echo "          && (cd web && npm install && npm run build) \\"
  echo "          && GOTOOLCHAIN=auto go build -o filefin ./cmd/filefin"
  exit 2
}

rm -rf "$RUN"
mkdir -p "$RUN/home" "$RUN/data"
export HOME="$RUN/home"
DATA="$RUN/data"

FILMS="$DATA/Films/(2020) Direct Play Movie"
SHOWS="$DATA/Shows/(2019) Transcode Show"
mkdir -p "$FILMS" "$SHOWS"
echo '{"id":1,"alias":"Films","position":0}' > "$DATA/Films/config.json"
echo '{"id":2,"alias":"Shows","position":1}' > "$DATA/Shows/config.json"

echo "seeding media..."
ffmpeg -nostdin -loglevel error -y \
  -f lavfi -i testsrc=duration=3:size=320x240:rate=15 \
  -f lavfi -i sine=frequency=440:duration=3 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  "$FILMS/(2020) Direct Play Movie.mp4"

ffmpeg -nostdin -loglevel error -y \
  -f lavfi -i testsrc=duration=3:size=320x240:rate=15 \
  -f lavfi -i sine=frequency=440:duration=3 \
  -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -c:a aac -shortest \
  "$SHOWS/(2019) Transcode Show - 1x1.mkv"

printf '1\n00:00:00,000 --> 00:00:02,000\nHello fixture\n\n' \
  > "$FILMS/(2020) Direct Play Movie.en.srt"

echo "setup..."
SETUP_OUT=$("$BIN" setup --data "$DATA" --port "$PORT" --bind 127.0.0.1 2>&1)
TOKEN=$(echo "$SETUP_OUT" | grep -oE 'token=[A-Za-z0-9_-]+' | head -1 | cut -d= -f2)
[ -n "$TOKEN" ] || { echo "FATAL: no setup token in:"; echo "$SETUP_OUT"; exit 2; }

"$BIN" serve > "$RUN/seed-server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
B="http://127.0.0.1:$PORT"
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

echo "install..."
curl -fsS -X POST "$B/api/install" -H 'Content-Type: application/json' \
  -H "X-Setup-Token: $TOKEN" \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\",\"dataDir\":\"$DATA\",\"token\":\"$TOKEN\"}" \
  >/dev/null

# Install triggers a reload; wait for the server to come back without the
# install routes before driving authenticated calls.
sleep 2
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

C="$RUN/cookies"
curl -fsS -c "$C" -X POST "$B/api/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\"}" >/dev/null

echo "rebuilding cache..."
curl -fsS -b "$C" -X POST "$B/api/admin/rebuild" -d '{}' >/dev/null || true
for _ in $(seq 1 60); do
  PROG=$(curl -fsS -b "$C" "$B/api/admin/rebuild/progress" 2>/dev/null || echo '{}')
  case "$PROG" in *'"finished":true'*) break;; esac
  sleep 0.5
done

MEDIA=$(curl -fsS -b "$C" "$B/api/admin/summary" | sed -n 's/.*"media":\([0-9]*\).*/\1/p' | head -1)
if [ "${MEDIA:-0}" -lt 2 ]; then
  echo "FATAL: expected 2 media items after rebuild, cache reports ${MEDIA:-0}"
  exit 1
fi

echo "seeded: $DATA  ($MEDIA media)  user=$USER_NAME port=$PORT"
