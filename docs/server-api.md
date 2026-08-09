# FileFin server API — the contract we observe

**Verified against:** FileFin `v0.20.3`, commit
`9399feb8f2f20cfad9f8d5be070d723faff5b3f6`. Source read 2026-08-08. Every
shape below is cited to the upstream file and line that proves it, and every
endpoint we call has a captured payload under `test/fixtures/`
(`test/fixtures/PROVENANCE.md` says which request produced which file).

This is an **external boundary** (CLAUDE.md §8). We do not control this server.
When upstream changes, the fixture and this document change together, and the
version above moves with them.

**Scope: user-facing routes only.** The server exposes **66** `/api/admin/*`
routes (counted at this commit: `grep -cE 'mux\.Handle\("[A-Z]+ /api/admin'
internal/server/server.go`) covering imports, Plex/Jellyfin migration, optimizer
control, user management and metadata matching. SPEC.md N1 and C4 exclude all of them —
they stay in the web UI, and the client is read-only against the library except
for its own watch state. `tool/testserver/seed.sh` calls two admin routes to
build a test library; nothing in `filefin_api` ever will.

Line numbers are `internal/…` paths in the upstream tree at that commit.

---

## Conventions

**Base URL.** Every path below is appended to the server's base URL, which may
itself carry a path prefix (`https://host/filefin`). `FileFinUrls` (M1.6) joins
them through `Uri`, never string concatenation.

**Encoding.** Every JSON response is written by `writeJSON`
(`server/server.go:463`), which sets `Content-Type: application/json` and
encodes with the standard library. Numbers are JSON numbers, never strings.

**Authentication.** Everything except `GET /api/state`, `POST /api/login` and
`POST /api/logout` is wrapped in `s.auth(...)` (`server/server.go:259-284`).
The middleware (`server/auth.go:79-93`) reads the `filefin_session` cookie and
answers `401 unauthorized` — as a plain-text body, not JSON — when the cookie
is absent *or* names a session the in-memory store no longer knows.

**A 401 is routine, not exceptional.** Sessions live in memory and die with the
process (SPEC.md L1). F3 re-authenticates and retries once, transparently. The
one exception: a `401` from `/api/login` itself means bad credentials, and
retrying it is an infinite loop.

**No path or method mismatch is ever answered with a 404 or a 405.** Read that
as being about *routing* only — a handler that DID match still returns real
404s for an unknown id or a missing file (`:380`, `:409`, `:435`, `:487` and
after), which is a different thing and is documented route by route below. `mux.Handle("/", s.spa())`
(`server/server.go:352`) is registered as a catch-all **outside** the
`if complete` block, and `spa()` (`server.go:380-403`) falls back to
`index.html` with `200 text/html; charset=utf-8` for any path it cannot serve
as a file. Verified live against v0.20.3:

```
GET /api/state                     200 application/json
GET /api/bogus                     200 text/html; charset=utf-8
GET /api/categories/               200 text/html; charset=utf-8   (trailing slash)
GET /api/mediaX                    200 text/html; charset=utf-8
GET /api/media/{id}/nope           200 text/html; charset=utf-8
GET /api/login                     200 text/html; charset=utf-8   (method mismatch)
PUT /api/media/{id}/favorite       200 text/html; charset=utf-8   (method mismatch)
```

So a typo'd path, a trailing slash from a `Uri` join, a method mismatch, and an
endpoint upstream later removes **all present as success**, and surface as a
JSON decode error rather than an HTTP one.

**On a 2xx response, a non-JSON `Content-Type` on a JSON route is a transport
failure, not a payload.** `filefin_api` checks the media type before decoding
and reports it as "this is not a FileFin API response", never as a malformed
model.

**The "on a 2xx" qualifier is load-bearing and was missing until M2.** Read
unconditionally, this paragraph contradicts the rest of this document: the same
server answers `401 unauthorized` and `404 page not found` as **plain text**
(above, and under `GET /api/media/{id}`). A client applying the media-type check
to every response would turn every documented error into "not a FileFin server"
— and F3 would never see a 401, so session recovery would never happen at all.
`filefin_api` applies it in `json_response.dart`, to 2xx bodies it intends to
decode, and `error_mapper.dart` never looks at a content type. This is also
why SPEC.md F1 probes for `application/json` plus `needsSetup`/`version` rather
than for a status code: `200` from `GET /api/state` is what *any* SPA host
answers, and proves nothing.

**No CORS headers are set anywhere.** Irrelevant to a native client; it is why
SPEC.md N5 rules out Flutter Web.

**Security headers are set on every response**, by `securityHeaders`
(`server/server.go:367-377`), which wraps the whole mux: `Content-Security-Policy`
(strict, no `unsafe-inline`; `server.go:360-362`), `X-Content-Type-Options:
nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`,
`Permissions-Policy: camera=(), microphone=(), geolocation=()`. HSTS is
deliberately omitted upstream (it belongs at the TLS edge). None of these
constrains a native client, but `nosniff` is the reason the `Content-Type` check
above is trustworthy: the server always declares a type and means it.

**No pagination anywhere.** No listing endpoint takes a limit, offset, or
cursor. A large library returns everything in one array (SPEC.md L2).

**`503 cache unavailable` does not mean "rebuilding".** Every route below that
lists it reaches it the same way: `ensureDB` failed, for *any* reason
(`server/media.go:192-198`). A rebuild in progress is one of those reasons and a
permanently unreadable cache directory is another — provoked live at v0.20.3
with `chmod 000` on the cache dir, which produced the identical `503`. The
status carries no way to tell them apart, which is why `CacheUnavailable`'s
message says "unavailable, possibly rebuilding" rather than promising a wait
that may never end.

**`files[].path` is relative to the data directory**, produced by
`relTo(dataDir, f.Path)`. The cache stores the path ABSOLUTE and `relTo`
returns its input unchanged when the row is not under `dataDir`, so a server
whose cache and data directory have been separated answers this field absolute —
which is a fact about a broken deployment, not a second documented shape.
`integration_test/support/fixture_run.dart` repoints the cache for exactly this
reason, and `browse_test.dart` asserts the relative form against the live
binary.

---

## `GET /api/state`

Reachability and version probe. **Unauthenticated** — this is F1's entire
mechanism for "is this a FileFin server at all".

Handler `handleState`, `server/install.go:24`.

| Go field | JSON key | Type | Notes |
|---|---|---|---|
| `NeedsSetup` | `needsSetup` | bool | true until an admin account exists |
| `Version` | `version` | string | the running binary's version, e.g. `"0.20.3"` |

Status: `200` always.

Fixture: `state.json` — `{"needsSetup":false,"version":"0.20.3"}`

The setup token is deliberately **not** exposed here (`install.go:22-23`); it
reaches a browser only through the URL the CLI prints. A client cannot drive
first-run setup, and should not try.

---

## `POST /api/login`

Handler `server/auth.go:132`.

Request: `{"username": string, "password": string}`.

On success sets cookie `filefin_session` (`auth.go:18`, set at `auth.go:177`):
`Path=/`, `HttpOnly`, `SameSite=Lax`, `Secure` when the request was TLS,
`Expires` in 7 days. The body is the same `authResult` as `/api/me`.

| Go field | JSON key | Type |
|---|---|---|
| `User` | `user` | string |
| `Admin` | `admin` | bool |
| `Alias` | `alias` | string |
| `MDLUsername` | `mdlUsername` | string |
| `MALUsername` | `malUsername` | string |

Defined at `server/server.go:447-453`.

| Status | When |
|---|---|
| `200` | credentials valid |
| `400` | body is not the expected JSON |
| `401` | wrong password, unknown account, or blocked account — **indistinguishable by design** (`auth.go:157-169` always runs exactly one bcrypt compare, against a dummy hash when the account does not exist, so the timing does not leak either) |
| `429` | rate limited, with a `Retry-After` header in whole seconds (`auth.go:148-150`) |

Rate limits (const block `server/loginlimit.go:15-27`, thresholds at `:16-22`): 5 failures per account in 15
minutes locks that account for 15 minutes; 20 failures per IP in 5 minutes
locks that IP for 15 minutes. A successful login clears the account counter.
Observed: eight consecutive wrong passwords gave `401 401 401 401 401 429 429
429` (`error_shapes.txt`).

The client honours `Retry-After` and must not treat a `401` here as a session
loss.

Fixture: `login.json`, and the 429 sequence in `error_shapes.txt`.
`login.json` is what the stub serves for this route in `filefin_api`'s unit
suite (`test/support/client_harness.dart`), and `client_endpoints_test.dart`
asserts all five of its keys. It used to be captured, checksummed and read by
nothing, with a hand-written literal carrying `user` and `admin` alone standing
in for it — which proves we can spell our own field names and nothing else (§8).

---

## `POST /api/logout`

Handler `server/auth.go:189`. Deletes the session server-side and clears the
cookie with Go's `MaxAge: -1` (`auth.go:195`), which goes on the wire as
`Max-Age=0` — that is the value a client-side cookie jar sees. Status `204`, no body. Unauthenticated (a stale cookie
logs out fine).

No fixture — the response is empty and carries no shape.

---

## `GET /api/me`

Handler `server/auth.go:200`. Returns the same `authResult` as login. This is
how F2 validates a restored session without sending a password.

| Status | When |
|---|---|
| `200` | session valid |
| `401` | no cookie, unknown session, or the user vanished from the config |

Fixture: `me.json`; the unauthenticated `401` is in `error_shapes.txt`.

---

## `GET /api/categories`

Flat list; the tree is assembled client-side from `parentId`. Handler
`server/library.go:66`, DTO `server/library.go:27-42`.

| Go field | JSON key | Type | Notes |
|---|---|---|---|
| `ID` | `id` | **int64** | not a string — CLAUDE.md §7 |
| `Name` | `name` | string | full relpath, e.g. `Anime/Seasonal` |
| `Leaf` | `leaf` | string | last path segment |
| `Alias` | `alias` | string | display name; may be empty |
| `ParentID` | `parentId` | int64 | **0 means top level**, not null |
| `OtherMedia` | `otherMedia` | bool | |
| `Position` | `position` | int | sort order among siblings |
| `Empty` | `empty` | bool | |
| `Media` | `media` | int | items in this category |
| `Files` | `files` | int | media files across those items |
| `Kind` | `kind` | string | `both` / `movie` / `show` |
| `Learned` | `learned` | int | import-hint count; no client use |

`media` and `files` are annotations from the cache; when the cache is
unavailable the listing still returns with both at **0** rather than failing
(`library.go:73-81`). A client cannot distinguish "empty category" from "cache
down" by these counts alone.

**Nesting is captured, not only documented (M3.2).** Until M3.2 the seeded
library was entirely flat, so every row in `categories.json` had `parentId: 0`
and the `name`/`leaf` distinction above — the thing a tree row is rendered from
— was asserted by nothing. Measured against the real binary at v0.20.3: a
directory *inside* a category directory, carrying its own `config.json` with a
`parentId`, becomes a real category with that parent.
`tool/testserver/seed.sh` now writes `Films/Documentaries/config.json`, and the
captured payload shows what a nested row looks like:

```json
{"id":3,"name":"Films/Documentaries","leaf":"Documentaries","alias":"Documentaries",
 "parentId":1,"position":0,"empty":true,"media":0,"files":0,"kind":"both"}
```

So `name` really is the full path and `leaf` really is what a tree row must
show — a UI rendering `name` prints `Films/Documentaries` on a row already
sitting under `Films`. `tool/check-fixtures.sh` asserts a non-zero `parentId`, a
`name` that differs from its `leaf`, and an `empty`/zero-count row are all still
present, so a re-capture that loses the nesting fails rather than quietly
narrowing what the fixture proves.

Status `200`, or `500` when the categories cannot be read from disk.

Fixture: `categories.json`.

---

## `GET /api/category/{id}/media`

Handler `server/media.go:203`. `{id}` is the int64 category id; a non-numeric
id is `400 bad category id`.

Returns `MediaSummary[]` (`db/media_query.go:12-19`), ordered **year then
title** (`db/media_query.go:25`).

| Go field | JSON key | Type | Notes |
|---|---|---|---|
| `ID` | `id` | string | 12 hex chars, `sha1(category + "/" + folder)[:12]` (`server/import.go:354`) |
| `Title` | `title` | string | |
| `Year` | `year` | int | 0 when unknown |
| `HasPoster` | `hasPoster` | bool | |
| `Watched` | `watched` | bool | per-user, overlaid from the `user_state` mirror (`server/search.go:50`) |
| `FolderPath` | — | — | `json:"-"`, never on the wire |

Only direct children — not the subtree. `ListMediaInCategorySubtree` exists
(`db/media_query.go:37`) but no user-facing route uses it.

Status `200`, `400` bad id, `500` query failure, `503` cache unavailable.

Fixture: `category_media.json`.

---

## `GET /api/home`

Handler `server/media.go:227`. Three `MediaSummary[]` rows in one call, newest
first by the per-user `updated` stamp.

| Go field | JSON key | Notes |
|---|---|---|
| `Continue` | `continue` | **a Dart reserved word** — the model needs `@JsonKey(name: 'continue')` |
| `Favorites` | `favorites` | |
| `Completed` | `completed` | |

Anonymous struct at `media.go:237-241`. Served from the `user_state` mirror
(three indexed queries), not a per-folder `meta.json` scan.

Status `200`, `500` query failure, `503` cache unavailable.

Fixture: `home_populated.json`.

---

## `GET /api/search?q=&field=`

Handler `server/search.go:16`. Returns `MediaSummary[]`, same ordering as a
category listing.

- `q` is trimmed. **An empty `q` returns an empty array, not the whole
  library** (`db/search.go:17-19`; the doc comment at `db/search.go:11-15` says so explicitly).
- `field` defaults to `all` when absent or empty.

The field vocabulary is `searchWhere`, `db/search.go:34-86`, and is **wider
than SPEC.md §3.2 lists**:

| `field` | Matches |
|---|---|
| `all` (and any unrecognised value) | title, description, plot, language, country, director, writer, plus the actor/genre/tag facets |
| `title` | `title LIKE` |
| `description` | `description LIKE` |
| `cast` | the `actor` facet |
| `genre` | the `genre` facet |
| `tag` | the `tag` facet |
| `language` | `language LIKE` |
| `director` | `director LIKE` |
| `writer` | `writer LIKE` |
| `year` | exact `year =`; a non-numeric `q` yields **no rows**, not an error |
| `decade` | `year BETWEEN d AND d+9` where `d = (n/10)*10` floored (`db/search.go:47`), `q` may carry a trailing `s` (`1990s`). `q=2015&field=decade` returns a 2019 item |

Two consequences for the client:

1. An unknown `field` **silently degrades to `all`** rather than erroring, so a
   typo produces plausible results. `SearchField` (M1.5) is an enum for exactly
   this reason.
2. `year` and `decade` are the only numeric scopes, and both fail closed on
   junk input.

Status `200`, `500` search failure, `503` cache unavailable.

Fixtures: `search_results.json`, `search_empty.json`.

---

## `GET /api/tags`

Handler `server/tags.go:49`, query `db/tags.go:19`. The curated tag vocabulary
with per-tag item counts, ordered by count descending then tag.

| Go field | JSON key | Type |
|---|---|---|
| `Tag` | `tag` | string |
| `Count` | `count` | int |

Defined at `db/tags.go:11-14`.

Documented and captured, but **no `Tag` model exists in M1** — no requirement
consumes the vocabulary yet, and CLAUDE.md §1 says the model arrives with the
screen that needs it.

Fixture: `tags.json`.

---

## `GET /api/media/{id}`

The detail payload. Handler `server/media.go:255`, DTOs `server/media.go:30-75` (`subtitleInfo` :30, `fileInfo` :36, `pair` :51, `mediaDetail` :56).

| Go field | JSON key | Type |
|---|---|---|
| `ID` | `id` | string |
| `Title` | `title` | string |
| `Year` | `year` | int |
| `Description` | `description` | string |
| `Plot` | `plot` | string |
| `HasPoster` | `hasPoster` | bool |
| `Files` | `files` | `fileInfo[]` |
| `Metadata` | `metadata` | `pair[]` |
| `Ratings` | `ratings` | `pair[]` |
| `Technical` | `technical` | `pair[]` |
| `Actors` | `actors` | string[] |
| `Genres` | `genres` | string[] |
| `Tags` | `tags` | string[] |
| `Watched` | `watched` | bool |
| `Favorite` | `favorite` | bool |
| `Rating` | `rating` | int, 0 = unrated |
| `ContinueIndex` | `continueIndex` | int |
| `ContinueSeconds` | `continueSeconds` | int |

Every list is initialised to an empty slice before use (`media.go:273-278`), so
these arrive as `[]`, never `null`. We decode them tolerantly anyway (§8): the
guarantee is upstream's, not ours.

`fileInfo` (`server/media.go:36-49`) — note it carries **`index` and `name`**,
which SPEC.md §3.3 omitted:

| Go field | JSON key | Type | Notes |
|---|---|---|---|
| `Index` | `index` | int | 0-based; the `{n}` in every playback path |
| `Name` | `name` | string | basename on disk |
| `Path` | `path` | string | relative to the data dir |
| `Size` | `size` | **int64** | the only bandwidth signal we get — F13's whole basis |
| `Season` | `season` | int | **0** for a single-file item |
| `Episode` | `episode` | int | **0** for a single-file item |
| `Ext` | `ext` | string | with the dot, e.g. `.mkv` |
| `Transcode` | `transcode` | bool | **the server's verdict** that this file is not browser-native |
| `Watched` | `watched` | bool | derived per-file, see Resume semantics |
| `Subtitles` | `subtitles` | `subtitleInfo[]` | sidecars only |

`subtitleInfo` (`media.go:30-34`): `{index: int, lang: string, label: string}`.

`pair` (`media.go:51-54`): `{key: string, value: string}`. **`key` is a display
label, not a stable identifier.** `orderedPairs` (`media.go:101`) maps known
`meta.json` keys through `metadataLabels`/`ratingLabels` (`media.go:80,93`) —
`release` becomes `Released`, `imdb` becomes `IMDb` — and any unlisted key
falls through in sorted order under its **raw name**. So the client must render
these, never key off them. The captured fixture deliberately contains a
`customKey` entry to keep that honest.

`technical` is not raw ffprobe output either: it is pre-formatted for display
(`technicalPairs`, `media.go:126`) — `Resolution` is `"320x240"`, `Duration` is
`"0:03"`.

A missing `meta.json` is **non-fatal** (`media.go:282`): the cache row still
supplies id, title, year, description, plot and files, and the rich blocks come
back empty.

Status `200`, `404` unknown id, `500` files could not be loaded, `503` cache
unavailable.

**`400` on the write routes is `BadRequest`, added at M4.** Two shapes, both
captured live at v0.20.3 into `test/fixtures/error_shapes.txt`:
`POST .../progress` with a `file` outside `files[]` answers
`400 bad file index` (`media.go:511`), and `POST .../rating` outside 1..10
answers `400 rating out of range` (`media.go:425`). It is deliberately **not**
retryable — a progress reporter that retried one would post the same rejected
body on every tick — which is why it is its own variant rather than
`ServerFailure`.

**Do not match on a 404 body string.** This is the ONE route whose 404 body is
the plain text `not found` (`media.go:264`). Every other user-facing 404 —
`poster` (`media.go:374`, `:388`), `progress` (`media.go:522`), and all of
`playback.go` — goes through `http.NotFound`, whose body is `404 page not
found`. A client keying off the body is wrong five times out of six; key off the
status.

Fixtures: `media_detail_directplay.json` (single file, `transcode:false`, one
sidecar subtitle, all rich fields populated),
`media_detail_transcode.json` (two files, `transcode:true`),
`media_detail_with_state.json` (favorite, rating 8, pointer at 2s),
`media_detail_multifile_advanced.json` (`continueIndex:1` after a 90% crossing).

---

## `GET /api/media/{id}/poster[?size=]`

Handler `server/media.go:351`. Image bytes via `http.ServeFile`, so the
`Content-Type` follows the file and byte ranges work.

`size` ∈ `detail` | `tile` serves the pre-built sized WebP variant **when it
exists**, and otherwise silently falls back to the base poster. Any other value
(including absent) serves the base poster. So `size` is a hint, not a contract:
the client cannot rely on getting the size it asked for and must not assume the
returned dimensions.

Status `200`, or `404` when the item has no poster at all — which is the normal
answer for an un-enriched library, and must not be surfaced as an error.
`filefin_api`'s `posterBytes` returns **null** for that 404 and keeps every
other status in the sealed error hierarchy, so a `503` never reads as "you have
no artwork".

**Fixture: `poster.jpg` (added M3.3; this section previously said "No
fixture").** The old reasoning had two halves and both were reconsidered.

*"The seeded items have no poster"* stopped being true. Measured against the
real binary at v0.20.3: the importer picks up a file named exactly `poster.jpg`
in a media folder and writes it into the cache's `media.poster` column, which is
what `hasPoster` is derived from (`(m.poster <> '')` in the summary query).
`tool/testserver/seed.sh` now copies one into the **film** and deliberately not
into the **show**, so both branches — bytes, and the 404 that means "no poster"
— have a real server behind them. Before this, every captured payload said
`hasPoster:false`, so a client that never handled `true` looked healthy.

*"A binary blob no model decodes"* is true and is not the point. What the
fixture asserts is not a decode: it is that `http.ServeFile` returns the seeded
bytes **unchanged**. The seed input is a committed file
(`tool/testserver/poster.jpg`) rather than a fresh `ffmpeg` encode, which is
what makes the captured fixture reproducible — an encode would produce different
bytes on a different libjpeg and rewrite the SHA-256 manifest on every machine.
The two files are byte-identical by construction, and
`integration_test/browse_test.dart` asserts exactly that against the live
server.

`tool/check-fixtures.sh` asserts that some item has `hasPoster: true` and that
the show still has `false`, so a re-seed that loses either branch fails.

---

## `GET /api/media/{id}/file/{n}` — the binding constraint

Handler `server/handleStream`, `server/playback.go:97`. The single most
consequential endpoint in the API (SPEC.md §3.4, L3).

The response is decided **entirely from the file's probed codecs**
(`playbackTarget`, `playback.go:67`; `fileNeedsTranscode`, `playback.go:78`).
There is no query parameter, header, or user-agent that changes it — verified:
`playback.go` contains no `Query().Get`.

| Condition | Response |
|---|---|
| a fresh `.optimized.mp4` sibling exists | `200`/`206` those bytes |
| probed container + codecs are browser-native | `200`/`206` the source, via `http.ServeContent` — full seek |
| needs transcoding, transcoding enabled | **`307`** → `Location: <this path>/hls/index.m3u8` (`playback.go:118`) |
| needs transcoding, transcoding disabled | **`415`** `transcoding disabled` (`playback.go:115`) |
| `{n}` not an integer | `400 bad file index` (`playback.go:100`) |
| no such file index | `404 page not found` (`playback.go:109`, `:123`) |
| the cache is unavailable | `503 cache unavailable` (`playback.go:103` -> `userPool`, `media.go:196`) |
| the file exists but cannot be stat'd | `500 internal error` (`playback.go:127-131`) |

`fileNeedsTranscode` judges by the **probed** container and codecs when the
cache row has them, falling back to the filename extension otherwise. That is
why a `.avi`-named H.264/MP4 direct-plays: the extension is not the decision.

```go
func fileNeedsTranscode(f db.MediaFile) bool {          // playback.go:78-83
    if f.Container != "" && f.VideoCodec != "" {
        return !transcode.DirectPlayable(f.Container, f.VideoCodec, f.AudioCodec)
    }
    return transcode.NeedsTranscode(f.Ext)
}
```

**Which branch you are in is a property of the ROW, not of the file**, and it is
the single easiest thing to measure wrongly here. The fallback's whole
vocabulary is `directPlay = {.mp4, .webm, .m4v}` (`transcode.go:42`); the
authority is `DirectPlayable`, whose `mkvFamily = {matroska, webm}` crossed with
`webmVideo = {vp8, vp9, av1}` and `webmAudio = {opus, vorbis, ""}` says a
VP9/Opus Matroska is direct-playable whatever the file is called
(`transcode.go:84`).

**`tool/testserver/seed.sh` never probes.** It rebuilds the cache and stops, so
`media_files.container`, `.video_codec` and `.audio_codec` are `''` for every
seeded row and `probe_tasks` is empty — *every* verdict any suite takes from the
seeded library is the extension fallback. The probe agent is queued by
`POST /api/admin/probe/scan` (`probe.go:37`) and by nothing the seed does.
`tool/spikes/e5_mkv_direct_play.sh` runs both arms over one VP9/Opus `.mkv`:
unprobed → `transcode:true` and `307`; probed (`matroska,webm` / `vp9` / `opus`)
→ `transcode:false` and `200` with `Accept-Ranges: bytes`. Measured at v0.20.3.

The `transcode` flag in the detail payload is this same verdict, computed by
the same function and told to us in advance. **`decide()` must use it and must
not reimplement `transcode.DirectPlayable`** — a second copy would drift from a
decision the server has already made.

Observed byte-range behaviour on the direct-play file (`error_shapes.txt`):

```
Range: bytes=0-49  ->  HTTP/1.1 206 Partial Content
                       Accept-Ranges: bytes
                       Content-Range: bytes 0-49/42953
                       Content-Length: 50
                       Content-Type: video/mp4
```

The `307` observed on the HEVC file:

```
HTTP/1.1 307 Temporary Redirect
Location: /api/media/919ac9caad25/file/0/hls/index.m3u8
```

R1 (retired, `tool/spikes/r1_headers_across_redirect.sh`) proved the `Cookie`
header survives that redirect and reaches the segment requests, so a single
`httpHeaders` map covers both branches.

---

## `GET /api/media/{id}/file/{n}/hls/index.m3u8`

Handler `handleHLSPlaylist`, `server/playback.go:160`; the gate is
`streamTarget` at `playback.go:138`.

`Content-Type: application/vnd.apple.mpegurl`. The playlist is a **VOD**
playlist listing every segment with `#EXT-X-ENDLIST` up front, so seeking works
— at the cost of a server-side transcode repositioning one ffmpeg run.

**The symmetric half of the constraint.** `playback.go:153-155` returns
**`415 not transcodable`** when transcoding is off **or the file does not need
transcoding**. So a browser-native file cannot be transcoded on request, just
as a non-native one cannot be served raw. There is no quality, bitrate, or
resolution parameter anywhere. This is what defeats network-adaptive playback
(SPEC.md §5.4, D4) and is why F13 is a guard rather than a switch.

**Two different 415s exist, and this client can only ever receive one of them.**
Both are captured in `error_shapes.txt`, and the distinction is worth one
paragraph because F12 promises to explain "a 415" and a maintainer who read
that literally would widen the message to cover a case that cannot arrive:

| Route | Body | When | Reachable from this client? |
|---|---|---|---|
| `.../file/{n}` | `transcoding disabled` | the file needs transcoding and the server has it off (`playback.go:115`) | **yes — this is F12's** |
| `.../file/{n}/hls/index.m3u8` | `not transcodable` | transcoding is off **or the file does not need it** (`playback.go:153`) | no |

`PlaybackRequest.url` is always the **file** route and libmpv follows the `307`
itself, so nothing in `filefin_api` ever requests the hls route — `hlsIndex` and
`hlsSegment` exist on `FileFinUrls` and have no production consumer, which is a
decision recorded in `urls.dart` rather than an oversight. `TranscodingDisabled`
therefore carries no body: only one shape can reach it, and under the `HEAD`
pre-flight that shape has no body at all (measured, M5.0/E-K).

Status `200`, `400` bad `{n}`, `404` no such file, `415` not transcodable,
`500` transcode failed, `503` cache unavailable.

Fixture: `hls_index.m3u8`; the `415` in `error_shapes.txt`.

---

## `GET /api/media/{id}/file/{n}/hls/{seg}`

Handler `server/playback.go:183`. `Content-Type: video/mp2t`, served with
`http.ServeFile`.

**Authenticated like every other route** (`server/server.go:283`) — the segment
requests carry the session cookie, which is the whole reason R1 mattered.

A not-yet-produced or already-reaped segment answers `503 segment unavailable`,
and that is **routine**: the client re-requests. It is not logged upstream and
must not be surfaced as an error.

No fixture (multi-megabyte binary, nothing in `filefin_core` parses it); R1's
spike confirmed `seg0.ts` returns `200 video/mp2t`.

---

## `GET /api/media/{id}/file/{n}/sub/{k}`

Handler `server/playback.go:202`. Returns the **k-th sidecar** subtitle
converted SRT→WebVTT per request. `Content-Type: text/vtt; charset=utf-8`.

Embedded subtitle tracks are externalised at import time, not at play time, so
what `subtitles[]` lists is all the API can offer. (libmpv can render embedded
tracks itself on the direct-play path; whether to surface those too is deferred,
SPEC.md §11.)

Conversion is best-effort and streamed: a mid-stream failure cannot be reported
once headers are sent (`playback.go:248`), so a truncated body is possible and
the client must tolerate it.

Status `200`, `400` bad `{n}` or `{k}`, `404` unknown media, unknown file, or
`{k}` out of range.

Fixture: `subtitle.vtt`.

---

## Watch state

Six mutating routes, all `204 No Content` on success and all writing
`meta.json` in the media folder under a per-user key — filesystem truth, not
cache, so the state survives a cache rebuild (`internal/state/state.go:1-11`).

### `POST /api/media/{id}/progress`

Handler `server/media.go:503`. Body:

```json
{"file": int, "position": float, "duration": float, "event": string}
```

`event` is accepted and **ignored by the engine** — nothing in `state.Apply`
reads it. `position` and `duration` are seconds.

| Status | When |
|---|---|
| `204` | applied |
| `400` | malformed body, **or `file` out of range** (`media.go:531`) |
| `404` | unknown media id |
| `500` | the `meta.json` write failed, **or** the file list could not be loaded (`media.go:527`) |
| `503` | cache unavailable |

**The out-of-range case differs between layers, and both readings are right.**
The HTTP handler rejects it with `400`. The engine `state.Apply`
(`state/engine.go:57-59`) returns the state **entirely unchanged**, `watched`
included. `filefin_core` mirrors the *engine*, because that is the function
whose rules the optimistic UI must reproduce; the `400` is `filefin_api`'s
concern. SPEC.md §3.5 describes the engine's behaviour.

### `DELETE /api/media/{id}/progress`

Handler `server/media.go:443`. Clears the pointer only; `watched`, `favorite`
and `rating` are untouched. `204`.

### `POST /api/media/{id}/watched` vs `DELETE /api/media/{id}/watched`

**These are not the same operation and the difference is deliberate.**

| Route | Effect | Source |
|---|---|---|
| `POST` `{"watched": bool}` | sets/clears the flag, **keeps the pointer** | `media.go:463-483` |
| `DELETE` | clears the flag **and nils the pointer** | `media.go:485-499` |

The upstream comments say why (`media.go:458-462`, `media.go:492`): the home
`continue` bucket already excludes a watched item, so `POST {"watched":false}`
returns the item to *continue where you left off*. `DELETE` is the home page's
"remove from completed" — dropping the pointer too, so the item leaves every
list. A leftover pointer would bounce it straight back into `continue`.

`filefin_core` exposes these as **two functions** (`setWatched`,
`clearWatched`), never one with a boolean. A single function with a flag makes
the asymmetry invisible at the call site, which is how the UI would come to
disagree with the server.

`POST` returns `400` on a malformed body; both return `404` on an unknown id,
and both can return `503 cache unavailable` — every one of these routes resolves
the folder through `folderFor` -> `userPool` (`media.go:382-385`).

### `POST /api/media/{id}/favorite`

Handler `server/media.go:394`. Body `{"favorite": bool}`. `204`; `400`
malformed; `404` unknown id; `503` cache unavailable (`folderFor` ->
`userPool`, `media.go:382-385`).

### `POST /api/media/{id}/rating`

Handler `server/media.go:417`. Body `{"rating": int}`. **1–10 valid, 0 clears**;
anything outside `0..10` is `400 rating out of range` (`media.go:425`). Also
`404` unknown id and `503` cache unavailable, via the same `folderFor` path.

The rating is independent of the resume engine: `Apply` never touches it and
clearing `watched` never clears it (`state/state.go:25-28`).

---

## Resume semantics

This is the specification `filefin_core`'s resume engine must match exactly. It
is a transcription of `internal/state/engine.go` at v0.20.3, rule by rule, and
`test/fixtures/resume_vectors.json` holds 601 input→output pairs captured from
these very functions as a differential oracle.

### Addressing

The server addresses the pointer by a **ref string**, not an index
(`Refs`, `state/engine.go:17-31`; the `Pointer` it writes is
`state/state.go:15-18`):

| File | Ref |
|---|---|
| season > 0 **and** episode > 0 | `"SxE"`, e.g. `1x2` |
| the only file in the folder | `""` |
| otherwise | `"#N"`, 1-based |

The client works in indices, because that is what `fileInfo.index` and
`continueIndex` give it. The mapping holds for a stable file list, which is the
only list a single detail response describes. Note that `(0, 0s)` is
observationally equivalent to "no pointer" in the derived view.

**The client rule for that ambiguity is upstream's own, observed rather than
invented** (recorded at M4, closing the hole M1 left):

```js
hasResume = !watched && (continueIndex > 0 || continueSeconds > 0)
```
— `web/src/lib/app.svelte.js:423`. And `playFile(idx)` seeks **only** when
`idx == continueIndex` (`:864`), so picking a file other than the pointer's
starts it at the beginning. `filefin_core`'s `offerResume` and `startSecondsFor`
implement exactly that, which is why `(0, 0)` is never offered as a resume
position: the two readings are indistinguishable on the wire, so neither is
guessed.

### The `event` field

`POST .../progress` carries `{file, position, duration, event}` and **the engine
never reads `event`** — nothing in `state.Apply` touches it. Upstream's player
sends four values: `checkpoint`, `pause`, `ended`, `stop`
(`web/src/views/library/Player.svelte`). This client sends those four plus
`seek`, which is safe in the strongest sense available: no value of a field the
server ignores can change what it stores.

The same file is where the **reporting interval** comes from:
`if (Math.abs(el.currentTime - lastMark) >= 30)`. That is **30 seconds of media
time, not wall clock** — so nothing reports while playback is paused, and the
rule is testable with no clock at all.

### `Apply(state, refs, fileIndex, position, duration)` — `engine.go:56-85`

1. **Out of range is identity.** `fileIndex < 0 || fileIndex >= len(refs)`
   returns the state unchanged — `watched` included (`engine.go:57-59`).

2. **Crossing.** `crossed = duration > 0 && position/duration >= 0.90`
   (`engine.go:61`; the constant is `WatchedThreshold` at `engine.go:7`).
   `duration <= 0` is **never** crossed, whatever the position. Note `>=`, not
   `>`: exactly 0.90 crosses.

3. **Target, before the pointer rules** (`engine.go:63-72`):
   - default: `targetIdx = fileIndex`, `targetSeconds = round(position)`
   - crossed **and** `fileIndex` is the last file → `watched = true`;
     `targetIdx` stays `fileIndex` and `targetSeconds` stays `round(position)`
   - crossed **and not** the last file → `targetIdx = fileIndex + 1`,
     `targetSeconds = 0`

4. **Rounding** is Go's `int(x + 0.5)` with a negative clamp to 0
   (`engine.go:43-48`): `x < 0 ? 0 : (x + 0.5).toInt()`. **Not Dart's
   `.round()`** — the two differ for negative values, and `-0.5` is reachable.

5. **Current index** is `-1` when there is no pointer (`engine.go:74-77`), so
   the first report on file 0 always installs one. It is also `-1` when the
   stored ref is not in `refs` at all, which happens when files are added or
   renamed between sessions.

6. **The pointer only moves forward** (`engine.go:78-83`), two cases only:
   - `targetIdx > curIdx` → write `{refs[targetIdx], targetSeconds}`
   - `targetIdx == curIdx` **and not crossed** and `targetSeconds >
     s.Progress.Seconds` → write the same
   - anything else leaves the pointer alone. Rewatching an earlier file does
     not regress it.

7. **The last-file asymmetry.** Case two requires `!crossed`. So when the last
   file crosses 90%, `watched` becomes true but the **seconds do not advance on
   that same report** — the pointer keeps whatever seconds it had. Captured:
   pointer `1x3@45`, report `95/100` → `watched:true`, pointer still `1x3@45`.
   Only when there is no pointer at that index does branch one fire and write
   `95`.

**Client-side hardening not present upstream:** Dart's `.toInt()` throws on NaN
and Infinity where Go's `int()` does not, so the client guards non-finite
`position`/`duration` before rounding. That is a decision about our runtime,
not a claim about the server.

### `View(state, refs)` — `engine.go:98-112`

`View` resolves the pointer to an index ONCE, with
`ptr = indexOf(refs, s.Progress.File)` (`engine.go:100-103`), and every row below
reads from `ptr`, never from the pointer directly:

| Field | Rule |
|---|---|
| `watched` | the folder flag verbatim |
| `continueIndex` | `ptr` when `ptr >= 0`, otherwise **0** |
| `continueSeconds` | the pointer's seconds when `ptr >= 0`, otherwise **0** |
| `perFile[i]` | `watched || i < ptr` |

**A pointer whose ref is not in `refs` reads identically to no pointer.**
`indexOf` returns `-1` for an unknown ref (`engine.go:102`), and the `if ptr >= 0`
guard at `engine.go:104-107` then leaves `ContinueIndex` and `ContinueSeconds` at
**0 even though `Progress != nil`**, with every `perFile` false. This is not
exotic — it is what a renamed or renumbered folder leaves behind between
sessions — and it is the only case that separates a correct implementation from
`continueSeconds = pointer?.seconds ?? 0`. `resume_vectors.json` carries 116
stale-ref inputs, 18 of which pin `out.pointer.seconds != 0` against
`view.continueSeconds == 0`. The wrong implementation passes every other
vector, and passed all 333 of the vectors captured before this was noticed.

`perFile` is what the detail response's `files[].watched` carries
(`media.go:324-328`). Note that the file **at** the pointer is not marked
watched — you are in the middle of it. And when `watched` is set, every file
reads as watched regardless of the pointer.

---

## Routes we deliberately do not call

Listed so their absence is a decision rather than an oversight.

| Route | Why not |
|---|---|
| `/api/admin/*` (66 routes) | SPEC.md N1, C4 — admin stays in the web UI |
| `POST /api/install`, `GET /api/install/browse` | first-run setup; the token never reaches a client (`install.go:22-23`) |
| `/api/mdl/*`, `/api/mal/*`, `/api/profile/*` | MyDramaList / MyAnimeList sync, deferred (SPEC.md §11) |

`POST /api/media/{id}/tags` used to be listed here. It does not exist: the real
route is `POST /api/admin/media/{id}/tags` (`server.go:321`), behind
`s.admin(...)`. Listing it implied a user-facing route we choose to skip, when
tag writing is gated by the **server**, not by our policy.
