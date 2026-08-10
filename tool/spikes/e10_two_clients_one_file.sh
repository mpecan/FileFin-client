#!/usr/bin/env bash
# E-10 — two clients, one server, one file. Is the ffmpeg run keyed on the
# FILE or on the viewer? (`docs/verification-backlog.md` row D)
#
# `docs/server-api.md` promises "one repositionable ffmpeg run per session"
# and never defines *session*. The difference is user-visible: if the run is
# keyed on the file, a second viewer joins the first viewer's encoder and one
# of them seeking moves the other's encode head — and it looks exactly like a
# client defect, because the client cannot see any of it.
#
# **Upstream answers it outright, and this script confirms upstream.**
# `internal/server/playback.go` builds the key as
# `r.PathValue("id") + "/" + r.PathValue("n")` — media id and file index, with
# no user and no cookie in it — and `internal/transcode/hls.go` holds
# `sessions map[string]*session` (:54) whose `ensure` returns the existing
# session for a key it already has (:281). Each session owns exactly one
# `run *ffmpegRun`, "replaced on a seek relaunch" (:66), and `maybeReposition`
# (:240) is what replaces it.
#
# The instrument is the session's own temp directory: `ensure` calls
# `os.MkdirTemp("", "filefin-hls-")` per session, so counting those directories
# counts sessions. Row D's original experiment — two viewers, one seeking to
# 5:00 — needs a long seeded item and this does not.
#
# Three requests, and the middle one is the result:
#   A: user 1 asks for file 0's playlist   -> expect +1  (the counter moves)
#   B: user 2 asks for file 0's playlist   -> expect +0  (THE RESULT)
#   C: user 2 asks for file 1's playlist   -> expect +1  (it can still move)
# C is the negative control. Without it, a "+0" would be indistinguishable from
# an instrument that had stopped counting.
#
# Prerequisites: a seeded FileFin server (tool/testserver/seed.sh), curl.
# Usage: FILEFIN_BIN=... FILEFIN_RUN=... tool/spikes/e10_two_clients_one_file.sh
set -uo pipefail

BIN="${FILEFIN_BIN:-$HOME/development/filefin-test/filefin}"
RUN="${FILEFIN_RUN:-$HOME/development/filefin-test/run}"
PORT="${FILEFIN_PORT:-8099}"
USER_NAME="${FILEFIN_USER:-testuser}"
PASS="${FILEFIN_PASS:-TestPassw0rd!23}"
TRANSCODE_CATEGORY="${FILEFIN_TRANSCODE_CATEGORY:-2}"

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl not on PATH"; exit 2; }
[ -x "$BIN" ] || { echo "FATAL: filefin binary not found at $BIN"; exit 2; }

export HOME="$RUN/home"
B="http://127.0.0.1:$PORT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$BIN" serve > "$RUN/server-e10.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true; rm -rf "$TMP"' EXIT
for _ in $(seq 1 40); do curl -fsS "$B/api/state" >/dev/null 2>&1 && break; sleep 0.25; done

# Two INDEPENDENT cookie jars. Same account is enough and is the sharper case:
# if the key had any per-viewer component at all, two logins would still be two
# sessions, so a "+0" here cannot be explained by the account being the same.
login() {
  curl -fsS -c "$1" -X POST "$B/api/login" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASS\"}" >/dev/null \
    || { echo "FATAL: login failed"; exit 2; }
}
login "$TMP/a"
login "$TMP/b"

MEDIA="$(curl -fsS -b "$TMP/a" "$B/api/category/$TRANSCODE_CATEGORY/media" \
  | sed -n 's/.*"id":"\([0-9a-f]\{12\}\)".*/\1/p' | head -1)"
[ -n "$MEDIA" ] || { echo "FATAL: no media in category $TRANSCODE_CATEGORY"; exit 2; }
echo "media: $MEDIA"

sessions() { ls -d "${TMPDIR:-/tmp}"/filefin-hls-* 2>/dev/null | wc -l | tr -d ' '; }

ask() { # ask <jar> <file index>
  curl -fsS -o /dev/null -b "$1" "$B/api/media/$MEDIA/file/$2/hls/index.m3u8" \
    || echo "  (playlist request failed)"
  sleep 1
}

before=$(sessions)
ask "$TMP/a" 0; a=$(sessions)
ask "$TMP/b" 0; b=$(sessions)
ask "$TMP/b" 1; c=$(sessions)

echo
printf 'before                       : %s session dir(s)\n' "$before"
printf 'A: viewer 1, file 0          : %s  (delta %+d)\n' "$a" "$((a - before))"
printf 'B: viewer 2, SAME file       : %s  (delta %+d)   <- the result\n' "$b" "$((b - a))"
printf 'C: viewer 2, different file  : %s  (delta %+d)   <- negative control\n' "$c" "$((c - b))"
echo

rc=0
[ "$((a - before))" -eq 1 ] || { echo "INVALID: the first request did not create a session dir — the instrument is not measuring anything"; rc=2; }
[ "$((c - b))" -eq 1 ] || { echo "INVALID: a different file did not create a session dir — the counter had stopped moving, so B's zero proves nothing"; rc=2; }
if [ "$rc" -eq 0 ]; then
  if [ "$((b - a))" -eq 0 ]; then
    cat <<'EOF'
RESULT: the transcode session is keyed on the FILE, not on the viewer.
Two clients watching the same file share one ffmpeg run, and `maybeReposition`
(internal/transcode/hls.go:240) relaunches THAT run when either of them seeks
out of its reach. Segments already written stay on disk (:157, :252), so the
blast radius is the not-yet-encoded tail: the viewer who did not seek stalls
until the encoder comes back past them.

Nothing in this client can observe it, and nothing in this client can prevent
it — there is no parameter on the route. It is recorded so the symptom is
recognisable rather than diagnosed as a player bug.
EOF
  else
    echo "RESULT: a second viewer got its OWN session. Upstream has changed;"
    echo "        re-read internal/transcode/hls.go and docs/server-api.md."
  fi
fi
exit "$rc"
