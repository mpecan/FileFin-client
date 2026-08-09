# Fixture provenance

Every file in this directory is a **captured real payload**, not a hand-written
literal. CLAUDE.md §8: a literal we author ourselves proves only that we can
spell our own field names — it cannot catch a field the server spells
differently, a number that arrives as a string, or a rounding rule we did not
know about. (This capture found `continueSeconds` returning `2` for a reported
position of `1.5`; Go rounds with `int(x + 0.5)`, not toward zero.)

| | |
|---|---|
| Upstream | <https://github.com/xuedi/FileFin> |
| Tag | `v0.20.3` |
| Commit | `9399feb8f2f20cfad9f8d5be070d723faff5b3f6` |
| Captured | 2026-08-08 |
| Captured by | `tool/testserver/seed.sh` then `tool/testserver/capture_fixtures.sh` |
| Server | a real `filefin` binary built from that commit, over a freshly seeded temp data dir on `127.0.0.1:8099` |
| User | `testuser`, which **is** an admin account — `login.json` and `me.json` both carry `"admin":true`. Nothing here exercises a non-admin user; only admin-gated *routes* are out of scope (SPEC.md N1), not the flag. |

Re-capture with `just fixtures-seed && just fixtures-capture`, then
`bash tool/check-fixtures.sh accept` to refresh `SHA256SUMS`. A full re-seed
and re-capture was verified to reproduce every byte of this directory
identically, so an unexplained diff is a real change — either upstream's or
ours.

## The seeded library

Two categories, three media files, chosen so both playback branches and both
halves of the resume engine's file addressing are covered:

| Category (`id`) | Item | Files | Playback |
|---|---|---|---|
| `Films` (1) | `(2020) Direct Play Movie` | 1 × `.mp4`, H.264 + AAC, plus an `.en.srt` sidecar | raw bytes, byte-range |
| `Shows` (2) | `(2019) Transcode Show` | 2 × `.mkv`, HEVC + AAC (`1x1`, `1x2`) | `307` → HLS |

The film is single-file, so `season`/`episode` are `0` and its state ref is the
empty string. The show is two numbered episodes, so its refs are `1x1`/`1x2` —
the only way `continueIndex` can be non-zero in any of these payloads.

Both folders carry a hand-written `meta.json` with populated `metadata`,
`ratings`, `technical`, `actors`, `genres` and `tags`. Nothing else in the
harness fills them, and a fixture whose rich fields are all empty arrays would
let a decoder that silently drops them round-trip perfectly.

## What produced each file

Every request below carried the `filefin_session` cookie from `POST /api/login`
except the two marked unauthenticated. `{d}` = `e4285edb34d5`, the film;
`{t}` = `919ac9caad25`, the show. Ids are `sha1(category + "/" + folder)[:12]`
(`internal/server/import.go:354`), so they are stable across re-seeds.

| Fixture | Method + path |
|---|---|
| `state.json` | `GET /api/state` (unauthenticated) |
| `login.json` | `POST /api/login` `{"username","password"}` |
| `me.json` | `GET /api/me` |
| `categories.json` | `GET /api/categories` |
| `tags.json` | `GET /api/tags` |
| `category_media.json` | `GET /api/category/1/media` |
| `media_detail_directplay.json` | `GET /api/media/{d}` — before any state was written |
| `media_detail_transcode.json` | `GET /api/media/{t}` — before any state was written |
| `media_detail_with_state.json` | `GET /api/media/{d}` — after favorite, rating 8, and progress `{file:0, position:1.5, duration:3.0}` |
| `media_detail_multifile_advanced.json` | `GET /api/media/{t}` — after `watched:true` and progress `{file:0, position:2.9, duration:3.0}`, which crosses 90% of a non-last file and advances the pointer to `(1, 0s)` |
| `home_populated.json` | `GET /api/home` — after the state writes above |
| `search_results.json` | `GET /api/search?q=Movie&field=all` |
| `search_empty.json` | `GET /api/search?q=zzzznope&field=all` |
| `hls_index.m3u8` | `GET /api/media/{t}/file/0/hls/index.m3u8` |
| `subtitle.vtt` | `GET /api/media/{d}/file/0/sub/0` — SRT converted to WebVTT per request |
| `error_shapes.txt` | see below |
| `SHA256SUMS` | `bash tool/check-fixtures.sh accept` |
| `KEYS.txt` | `bash tool/check-fixtures.sh accept` — every JSON path ever captured, a ratchet the gate refuses to let shrink |

`resume_vectors.json` is the one file here that did **not** come from HTTP, and
the opening claim above needs that qualification: it is still a captured real
payload, but captured from the engine rather than from the wire.

| | |
|---|---|
| Produced by | `just fixtures-vectors` → `tool/capture-resume-vectors.sh` |
| How | `tool/fixtures/capture_state_vectors_test.go` is copied into a clone of upstream pinned to `9399feb` and run as `internal/state/capture_state_vectors_test.go`, calling the real `state.Apply` / `state.View` from inside the package |
| Contents | 601 input→output vectors over three ref shapes (`""`, `#N`, `SxE`), including 116 with a pointer whose ref is absent from `refs` |
| Why not HTTP | driving `Apply` over `POST /api/media/{id}/progress` folds in the handler's own validation (an out-of-range file index is a `400` at `media.go:531`, while the engine returns the state unchanged) and costs one request and one `meta.json` read-modify-write per vector |

The expectations are not written by hand: whatever the engine returned is what
was recorded. That is the entire value — a hand-written expectation can only
encode what we already believe about the function under test.

`error_shapes.txt` is a transcript, not a payload, because the interesting part
is the status line and the headers rather than a body:

**Every block the capture emits is listed here, and that completeness is the
point.** `check-fixtures.sh` puts this file in the SHA-256 manifest precisely so
the record of how a fixture was produced is tied to its bytes; a table that had
drifted to six of twelve sections tied the bytes to a description of something
else (M5.R/G-F2). `tool/testserver/capture_fixtures.sh` writes them in this
order.

| Section | Request |
|---|---|
| 401 | `GET /api/me` with no cookie |
| 404 | `GET /api/media/deadbeefdead` |
| 307 | `GET /api/media/{t}/file/0` — response headers only |
| 415 | `GET /api/media/{d}/file/0/hls/index.m3u8` — the symmetric refusal, `not transcodable` |
| 206 | `GET /api/media/{d}/file/0` with `Range: bytes=0-49` — headers only |
| 400 | `POST /api/media/{t}/progress` with `file: 99` — `bad file index` |
| 400 | `POST /api/media/{d}/rating` with `{"rating": 99}` — `rating out of range` |
| 200 | `GET /api/media/{d}/file/0/sub/0` — headers and the WebVTT the server converted the SRT into |
| 429 | eight consecutive `POST /api/login` with a wrong password |

The last three blocks are captured against **the same server restarted with
`transcodeEnabled: false`**, which the script writes into `.filefin.json` and
puts back from a pristine copy on the way out (its `EXIT` trap, whatever
happens). They are the only ones that need a differently configured server:

| Section | Request |
|---|---|
| 415 | `GET /api/media/{t}/file/0` — the FILE route's `transcoding disabled`, **the only 415 this client can receive** (F12) |
| detail | `GET /api/media/{t}` — `"transcode":true` on that same server, which is what keeps the client's guard firing (M5.0/E-B) |
| 200 | `GET /api/media/{d}/file/0` — the direct-play film is unaffected by the setting |

The 429 carries `Retry-After: 900`, verified live against this seeded server —
six wrong passwords give `401 401 401 401 401 429`, and the sixth carries the
header. It is `int(retry.Seconds()) + 1` over the remaining account lock
(`auth.go:149`), and username case variants share the bucket
(`config.NormalizeUsername`, `auth.go:145`).

## Known gaps

Stated so silence does not read as coverage. None of these is claimed by any
M1 model, so §8 is intact.

**"they land at M2/M5" was too broad, and M5 is where that shows.** M5 captured
the 415 a client can actually receive — the FILE route's `transcoding
disabled`, against a server whose `transcodeEnabled` this script switches off
and puts back — and deliberately did NOT capture segment bytes: they are
multi-megabyte, nothing in `filefin_core` parses them, and R1's spike already
confirmed `seg0.ts` answers `200 video/mp2t`. What is left open is listed
below with the milestone that would close it, rather than with a date that has
passed.

- ~~**Poster bytes.**~~ **Closed at M3.3.** `poster.jpg` is captured. The gap
  rested on "the seeded items have no poster", which stopped being true: the
  importer picks up a file named exactly `poster.jpg` in a media folder
  (measured at v0.20.3), so `seed.sh` copies a committed one into the **film**
  and deliberately not into the **show** — both branches now have a real server
  behind them. The remaining half of the old reasoning, that no model decodes a
  blob, is true and beside the point: what the fixture asserts is that
  `http.ServeFile` returns the seeded bytes unchanged. The seed input is a
  committed file rather than a fresh encode, so the capture is byte-reproducible
  on any machine — an `ffmpeg` run would rewrite the manifest on every one.
- **HLS segments.** `hls_index.m3u8` is captured; `seg0.ts` is not. It is
  multi-megabyte binary and nothing in `filefin_core` parses it. R1 already
  proved the segment fetch works end-to-end
  (`tool/spikes/r1_headers_across_redirect.sh`).
- **Header-level 307 behaviour as a client sees it.** `error_shapes.txt`
  records the status and `Location` from curl. Whether a *player* preserves the
  `Cookie` across it is R1's question, and R1 answered it empirically.
- **Multiple users.** Everything here is `testuser`. Per-user state isolation
  is untested.
