#!/usr/bin/env bash
# Seeds a real FileFin server for integration tests and fixture capture.
#
# Builds a library that exercises BOTH playback branches, because the whole
# playback design turns on the difference (SPEC.md §3.4):
#
#   Films/  (2020) Direct Play Movie.mp4    H.264 + AAC  -> served as raw bytes
#   Shows/  (2019) Transcode Show - 1x1.mkv HEVC  + AAC  -> 307 redirect to HLS
#                  (2019) Transcode Show - 1x2.mkv
#
# A sidecar .srt rides along so the subtitle endpoint has something to convert.
#
# The show is deliberately TWO files and the film exactly ONE. That covers both
# halves of the resume engine's addressing (internal/state/engine.go:17 Refs): a
# single-file folder's ref is the empty string with season/episode 0, a numbered
# episode's is "SxE" with both non-zero. It is also the only way the captured
# fixtures can show `continueIndex` moving off 0.
#
# Each folder gets a hand-written meta.json with populated metadata, ratings,
# technical, actors, genres and tags. Nothing else in this harness fills them,
# and a fixture whose rich fields are all empty arrays would let a decoder that
# silently drops them round-trip perfectly. Only the importer's admin flow ever
# writes meta.json, so these survive the cache rebuild.
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

# A NESTED category, and the reason it is here is that nothing else proves
# nesting exists. `GET /api/categories` returns a flat list and SPEC.md §3.2
# says the client assembles the tree; before M3.2 the seeded library had no
# non-zero `parentId` anywhere, so `buildCategoryTree`'s whole subject was
# tested against fabricated rows only.
#
# Measured against the real binary at v0.20.3: a directory inside a category
# directory, carrying its own config.json with `parentId`, becomes a real
# category with that parentId. Two facts came out of it that the UI depends on:
#
#   name  is the FULL PATH  — "Films/Documentaries"
#   leaf  is the DISPLAY NAME — "Documentaries"
#
# A tree that rendered `name` would print the whole path on every nested row.
#
# It holds no media deliberately: `media: 0` and `empty: true` then appear in a
# captured payload, and both were previously unexercised — a category listing
# whose counts are 0 is exactly the case the UI must not read as "empty
# library" (`library.go:73-81` returns 0 for both when the cache is down too).
mkdir -p "$DATA/Films/Documentaries"
echo '{"id":3,"alias":"Documentaries","position":0,"parentId":1}' \
  > "$DATA/Films/Documentaries/config.json"

echo "seeding media..."
ffmpeg -nostdin -loglevel error -y \
  -f lavfi -i testsrc=duration=3:size=320x240:rate=15 \
  -f lavfi -i sine=frequency=440:duration=3 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  "$FILMS/(2020) Direct Play Movie.mp4"

for ep in 1 2; do
  ffmpeg -nostdin -loglevel error -y \
    -f lavfi -i "testsrc=duration=3:size=320x240:rate=15" \
    -f lavfi -i "sine=frequency=$((440 * ep)):duration=3" \
    -c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -c:a aac -shortest \
    "$SHOWS/(2019) Transcode Show - 1x$ep.mkv"
done

printf '1\n00:00:00,000 --> 00:00:02,000\nHello fixture\n\n' \
  > "$FILMS/(2020) Direct Play Movie.en.srt"

# Rich metadata. `version` MUST be importer.MetaVersion (2, importer.go:26):
# anything lower trips upgradeMeta (importer.go:86), which treats the legacy
# `tags` key as genres and nils Tags — which is exactly how the first attempt at
# this produced a fixture with an empty tags array.
#
# The values are fabricated but their SHAPE is the server's:
# `metadata` and `ratings` are string maps the detail handler renders through
# metadataLabels/ratingLabels (media.go:80,93), so only listed keys get a
# friendly label and the rest fall through sorted under their raw name — which
# is why `customKey` is here, to prove the client does not assume the label set.
cat > "$FILMS/meta.json" <<'JSON'
{
  "version": 2,
  "title": "Direct Play Movie",
  "year": 2020,
  "description": "A short H.264 clip that the server serves as raw bytes.",
  "plot": "Colour bars meet a sine wave. Nothing else happens, at length.",
  "metadata": {
    "release": "2020-04-01",
    "runtime": "3 s",
    "language": "English",
    "origin": "Slovenia",
    "directedBy": "A. Seeder",
    "writtenBy": "B. Fixture",
    "contentRating": "PG",
    "awards": "None whatsoever",
    "boxOffice": "$0",
    "imdbID": "tt0000000",
    "customKey": "unlabelled keys fall through sorted, under their raw name"
  },
  "ratings": {
    "imdb": "7.1/10",
    "rottenTomatoes": "62%",
    "metacritic": "55/100"
  },
  "actors": ["Ada Lovelace", "Grace Hopper", "Alan Turing"],
  "genres": ["Test", "Short"],
  "tags": ["fixture", "direct-play"],
  "technical": {
    "duration": 3,
    "container": "mov,mp4,m4a,3gp,3g2,mj2",
    "videoCodec": "h264",
    "audioCodec": "aac",
    "width": 320,
    "height": 240
  },
  "enriched": true
}
JSON

cat > "$SHOWS/meta.json" <<'JSON'
{
  "version": 2,
  "title": "Transcode Show",
  "year": 2019,
  "description": "Two HEVC episodes the server refuses to serve as raw bytes.",
  "plot": "Season one, such as it is.",
  "metadata": {
    "release": "2019-09-15",
    "runtime": "3 s",
    "language": "Slovenian",
    "origin": "Slovenia",
    "directedBy": "C. Encoder",
    "contentRating": "TV-G",
    "imdbID": "tt1111111"
  },
  "ratings": {
    "imdb": "8.4/10"
  },
  "actors": ["Barbara Liskov"],
  "genres": ["Test"],
  "tags": ["fixture", "transcode"],
  "technical": {
    "duration": 3,
    "container": "matroska,webm",
    "videoCodec": "hevc",
    "audioCodec": "aac",
    "width": 320,
    "height": 240
  },
  "enriched": true
}
JSON

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

# The rich fields and the two-file item are the whole point of the enrichment
# above; if the rebuild dropped either, the fixtures would look fine and prove
# nothing. Assert them against what the API actually returns.
SHOW_ID=$(curl -fsS -b "$C" "$B/api/category/2/media" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
DETAIL=$(curl -fsS -b "$C" "$B/api/media/$SHOW_ID")
FILES=$(printf '%s' "$DETAIL" | grep -o '"index":' | grep -c . || true)
[ "$FILES" -eq 2 ] || { echo "FATAL: show should have 2 files, detail reports $FILES"; exit 1; }
case "$DETAIL" in
  *'"episode":2'*) ;;
  *) echo "FATAL: no episode 2 in the show detail — the SxE parse did not take"; exit 1;;
esac
case "$DETAIL" in
  *'"genres":["Test"]'*) ;;
  *) echo "FATAL: meta.json rich fields did not survive the rebuild"; exit 1;;
esac

echo "seeded: $DATA  ($MEDIA media, show has $FILES files)  user=$USER_NAME port=$PORT"
