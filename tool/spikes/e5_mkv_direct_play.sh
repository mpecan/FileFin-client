#!/usr/bin/env bash
# E5 — does the server direct-play a VP9/Opus Matroska, and what actually
# decides? (SPEC.md §3.4, §10's M4 row)
#
# M4's first pass measured a VP9+Opus `.mkv` 307ing to HLS and concluded that
# "browser-native" is decided by file EXTENSION. That conclusion was wrong, and
# this script is what shows why — by running BOTH arms of the same library.
#
# Upstream at v0.20.3, `internal/server/playback.go:78-83`:
#
#     func fileNeedsTranscode(f db.MediaFile) bool {
#         if f.Container != "" && f.VideoCodec != "" {
#             return !transcode.DirectPlayable(f.Container, f.VideoCodec, f.AudioCodec)
#         }
#         return transcode.NeedsTranscode(f.Ext)
#     }
#
# The extension is the FALLBACK for a row the probe agent has not reached
# (`directPlay = {.mp4, .webm, .m4v}`, `internal/transcode/transcode.go:42`).
# The authority, once the row carries a probed format, is `DirectPlayable`,
# whose `mkvFamily = {matroska, webm}` crossed with `webmVideo = {vp8,vp9,av1}`
# and `webmAudio = {opus,vorbis,""}` says a VP9/Opus Matroska IS direct-playable
# whatever the file is called.
#
# `tool/testserver/seed.sh` never probes: it rebuilds the cache and stops, so
# `media_files.container` is '' for every row and `probe_tasks` is empty. Every
# verdict measured against the seeded library is therefore the extension
# fallback — which is exactly the observation that was mistaken for the rule.
#
# THE SECOND ARM IS THE CONTROL. A spike with only arm 1 reproduces the wrong
# conclusion (CLAUDE.md, "Gates must be able to fail"): it is arm 2, after
# `POST /api/admin/probe/scan` has filled the format columns, that separates
# "the server decides by extension" from "this row was never probed".
#
# Prerequisites: the filefin binary, ffmpeg (with libvpx-vp9 and libopus),
# curl and sqlite3. It builds its OWN library in $FILEFIN_E5_RUN and never
# touches the shared seed at $HOME/development/filefin-test/run.
#
# Usage:  tool/spikes/e5_mkv_direct_play.sh
set -uo pipefail

BIN="${FILEFIN_BIN:-$HOME/development/filefin-test/filefin}"
RUN="${FILEFIN_E5_RUN:-$HOME/development/filefin-test/e5run}"
PORT="${FILEFIN_E5_PORT:-8098}"
USER_NAME="${FILEFIN_USER:-testuser}"
PASS="${FILEFIN_PASS:-TestPassw0rd!23}"

for tool in ffmpeg curl sqlite3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: $tool not on PATH"; exit 2; }
done
[ -x "$BIN" ] || { echo "FATAL: filefin binary not found at $BIN"; exit 2; }

rm -rf "$RUN"; mkdir -p "$RUN/home" "$RUN/data"
export HOME="$RUN/home"
DATA="$RUN/data"
F="$DATA/Films/(2021) Native Matroska"
mkdir -p "$F"
echo '{"id":1,"alias":"Films","position":0}' > "$DATA/Films/config.json"

ffmpeg -nostdin -loglevel error -y \
  -f lavfi -i testsrc=duration=3:size=320x240:rate=15 \
  -f lavfi -i sine=frequency=440:duration=3 \
  -c:v libvpx-vp9 -b:v 200k -pix_fmt yuv420p -c:a libopus -shortest \
  "$F/(2021) Native Matroska.mkv" || { echo "FATAL: ffmpeg cannot encode VP9/Opus"; exit 2; }

cat > "$F/meta.json" <<'JSON'
{"version":2,"title":"Native Matroska","year":2021,"description":"VP9+Opus in a .mkv","genres":["Test"],"enriched":true}
JSON

echo "--- what is actually inside the file ---"
ffprobe -v error -show_entries format=format_name -show_entries stream=codec_name \
  -of default=nw=1 "$F/(2021) Native Matroska.mkv"

TOKEN=$("$BIN" setup --data "$DATA" --port "$PORT" --bind 127.0.0.1 2>&1 \
  | grep -oE 'token=[A-Za-z0-9_-]+' | head -1 | cut -d= -f2)
[ -n "$TOKEN" ] || { echo "FATAL: no setup token"; exit 2; }

"$BIN" serve > "$RUN/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
B="http://127.0.0.1:$PORT"
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

curl -fsS -X POST "$B/api/install" -H 'Content-Type: application/json' \
  -H "X-Setup-Token: $TOKEN" \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\",\"dataDir\":\"$DATA\",\"token\":\"$TOKEN\"}" \
  >/dev/null
sleep 2
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

C="$RUN/cookies"
curl -fsS -c "$C" -X POST "$B/api/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\"}" >/dev/null
curl -fsS -b "$C" -X POST "$B/api/admin/rebuild" -d '{}' >/dev/null || true
for _ in $(seq 1 60); do
  PROG=$(curl -fsS -b "$C" "$B/api/admin/rebuild/progress" 2>/dev/null || echo '{}')
  case "$PROG" in *'"finished":true'*) break;; esac
  sleep 0.5
done

DB="$RUN/home/Library/Caches/filefin/cache.db"
ID=$(sqlite3 "$DB" "select media_id from media_files limit 1;")
[ -n "$ID" ] || { echo "FATAL: the rebuild cached no files"; exit 1; }

report() {
  sqlite3 -header -column "$DB" \
    "select idx, ext, quote(container) container, quote(video_codec) video_codec,
            quote(audio_codec) audio_codec from media_files;"
  echo "probe_tasks rows: $(sqlite3 "$DB" 'select count(*) from probe_tasks;')"
  echo "detail says: $(curl -fsS -b "$C" "$B/api/media/$ID" | grep -o '"transcode":[a-z]*' | head -1)"
  curl -s -o /dev/null -D - -b "$C" "$B/api/media/$ID/file/0" \
    | grep -iE '^HTTP/|^Accept-Ranges:|^Location:|^Content-Type:'
}

echo
echo "=========== ARM 1 — the row the probe agent has not reached ==========="
report
STATUS1=$(curl -s -o /dev/null -w '%{http_code}' -b "$C" "$B/api/media/$ID/file/0")

echo
echo "=========== triggering the probe agent ==========="
curl -fsS -b "$C" -X POST "$B/api/admin/probe/scan" -d '{}'; echo
for _ in $(seq 1 60); do
  [ "$(sqlite3 "$DB" "select count(*) from media_files where container <> '';")" -gt 0 ] && break
  sleep 0.5
done

echo
echo "=========== ARM 2 — the same file, now probed ==========="
report
STATUS2=$(curl -s -o /dev/null -w '%{http_code}' -b "$C" "$B/api/media/$ID/file/0")

echo
if [ "$STATUS1" = "307" ] && [ "$STATUS2" = "200" ]; then
  echo "RESULT: VALID — the extension only decides while the row is unprobed."
  echo "        Unprobed .mkv -> $STATUS1 (HLS).  Probed matroska/vp9/opus -> $STATUS2 (raw bytes)."
  echo "        So an MKV DOES direct-play, and SPEC.md §3.4 was right."
  exit 0
fi
echo "RESULT: INVALID — expected 307 then 200, got $STATUS1 then $STATUS2."
echo "        Either the probe agent did not run, or upstream's rule changed."
exit 1
