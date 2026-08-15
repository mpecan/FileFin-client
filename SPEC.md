# FileFin Client — Technical Specification

A mobile client for [FileFin](https://github.com/xuedi/FileFin), a
filesystem-first self-hosted media server (Go backend, Svelte web UI, EUPL
v1.2).

**Status:** M0-M7 complete. The workspace, every quality gate, the
git hooks and CI exist; `docs/server-api.md` records the contract and
`test/fixtures/` holds captured real payloads. `packages/filefin_core` holds
the wire models, the extension-type IDs, URL construction, the resume engine and
`decide()` — pure Dart, no I/O. `packages/filefin_api` holds the HTTP client:
typed endpoints, the cookie jar, F3's transparent 401 retry and F15's
certificate pinning, with `just it` running it against a real `filefin` binary.
`apps/mobile` holds the Flutter app: the shell, F1's add-server flow, F2's
sign-in and its cold-start restore, F4's category tree, virtualised poster grid
and detail view, F5's search, F6's home rows, F7–F9's player, F10's writes,
F11's server picker, F14's lock-screen transport and F15's accept-and-pin
dialog. `STATE.md` is the milestone-by-milestone record, its M7 section carries
the **full-spec audit** — every F-number and every §7 line, built or dropped
with a reason — and
`docs/verification-backlog.md` records every claim no test in this repository
can check, each with the experiment that would settle it.

**Verified against:** FileFin `master` @ v0.20.3, source read 2026-08-08.
Every claim in §3 cites the upstream file that proves it.

**Stack:** Flutter + Dart; playback by `media_kit` (libmpv) on Android and iOS.

---

## 1. Goals and non-goals

### Goals

- **G1.** Browse a FileFin library and play video from it on Android and iOS.
- **G2.** Play **everything in the library**, including MKV and HEVC, without
  asking the server to transcode where that can be avoided.
- **G3.** Full resume: report progress so watch state stays consistent with
  the web UI and any other client.
- **G4.** Multiple saved servers, each with its own credentials.
- **G5.** Be a *good citizen* of a server we do not own: tolerate schema
  additions, never require a modified server to function, degrade visibly
  rather than silently.

### Non-goals

- **N1.** Admin functionality. The server exposes ~50 `/api/admin/*` routes
  (imports, Plex/Jellyfin migration, optimizer control, user management,
  metadata matching). All of it stays in the web UI. We consume the ~20
  user-facing routes only.
- **N2.** Any local mirror of the library beyond a poster/response cache.
- **N3.** Desktop. Explicitly dropped — see §2.
- **N4.** Casting (Chromecast/AirPlay), or a remote-control protocol.
- **N5.** Flutter Web. `media_kit` falls back to HTML5 `<video>` there, which
  forfeits G2 entirely, and the browser reintroduces the CORS problem §3.1
  describes.

### Explicitly accepted limitations

- **L1.** Server sessions are **in-memory and lost on server restart**
  (`internal/server/auth.go`, `sessionStore`). Any session can become invalid
  at any moment with no warning. A `401` on any call is normal, not
  exceptional: re-authenticate and retry once (F3).
- **L2.** The server has **no pagination or result caps** on search, category,
  or home endpoints (`ROADMAP.md` milestone 1 lists this as outstanding for
  1.0). A large library returns everything in one array. Lists must be
  virtualised and must not assume bounded responses.
- **L3.** **Playback mode is not selectable in either direction** (§3.4). This
  is the single most consequential constraint on the design, and it defeats
  network-adaptive streaming (§5.4).

---

## 2. Why Flutter, and why not Tauri

The original brief was Tauri v2. It was abandoned once the target narrowed to
mobile only, on two findings:

1. **Tauri mobile cannot composite a player into the UI.** The established
   pattern ([tauri-plugin-videoplayer](https://github.com/yeonv/tauri-plugin-videoplayer))
   launches a *separate fullscreen native Activity* backed by androidx.media3
   and hands playback off. The webview UI is gone while video plays, so every
   player control — subtitle picker, next-episode, resume prompt, progress
   reporting — has to be reimplemented in native Kotlin and Swift anyway. For
   an app that is largely a video player, that is the native cost *plus* a
   bridge *plus* a JS UI.
2. **AVPlayer cannot play MKV**, the dominant container in self-hosted
   libraries. iOS therefore needs libmpv, VLCKit, or an FFmpeg engine
   regardless of framework. "Go fully native" does not avoid the C dependency;
   it is precisely why Infuse and VLC exist.

Given a libmpv-class engine is required on iOS either way, the deciding factor
is which stack already ships one. `media_kit` bundles prebuilt libmpv for iOS
(updated May 2026) and Android (Jan 2026) behind one Dart API — turning the
hardest problem into a dependency. The cost is Dart rather than Rust, and
platform integration (lock screen, PiP) needing extra work (§8, R2/R3).

Rejected alternatives: KMP + Compose Multiplatform (shared UI, but the iOS
player integration is ours to build); Rust core via UniFFI + two native UIs
(best result, roughly double the UI work).

---

## 3. The server contract

Read from source. Full endpoint table with citations lands in
`docs/server-api.md` at M0; this section records only what constrains the
architecture.

### 3.1 Authentication — session cookie, no CORS

`POST /api/login` with `{"username","password"}` sets an **HttpOnly**,
`SameSite=Lax`, 7-day cookie `filefin_session` and returns
`{user, admin, alias, mdlUsername, malUsername}` (`auth.go`; the `authResult`
struct is `server.go:447-453`, `authResultOf` that builds it is `:456`).
Every route we use sits behind `s.auth(...)` and needs that cookie.

**No CORS headers are set anywhere in the server** (verified: no `cors` or
`Access-Control` string in `internal/` or `web/`). This is fatal to a browser
client and irrelevant to us — Flutter's HTTP is native, not subject to the
same-origin policy. It is the reason N5 exists.

Login is rate-limited per-account and per-IP, returning `429` with
`Retry-After` (`auth.go`, `s.logins.allowed`). The client honours
`Retry-After`, and must not treat a `401` *from `/api/login` itself* as an L1
session loss — that way lies an infinite retry loop.

### 3.2 Library browsing

| Route | Returns |
|---|---|
| `GET /api/state` | `{needsSetup, version}` — unauthenticated; reachability + version probe |
| `GET /api/me` | current user; validates a restored session |
| `GET /api/categories` | flat list with `parentId`, `position`, `media`, `files` — tree assembled client-side |
| `GET /api/category/{id}/media` | `MediaSummary[]`, ordered year then title |
| `GET /api/home` | `{continue, favorites, completed}`, each `MediaSummary[]`, newest-first **by the per-user `updated` stamp, out of the `user_state` MIRROR rather than `meta.json`** (`media.go:227`) |
| `GET /api/search?q=&field=` | `MediaSummary[]`; `field` ∈ all/title/description/cast/genre/tag/language/director/writer/year/decade — **eleven**, and this row listed seven until M6 |
| `GET /api/tags` | tag list |
| `GET /api/media/{id}` | full detail (§3.3) |
| `GET /api/media/{id}/poster` | poster image bytes |

`MediaSummary` = `{id, title, year, hasPoster, watched}`
(`internal/db/media_query.go:12`).

### 3.3 Media detail

`internal/server/media.go:56` — `{id, title, year, description, plot,
hasPoster, files[], metadata[], ratings[], technical[], actors[], genres[],
tags[], watched, favorite, rating, continueIndex, continueSeconds}`.

`files[]` = `{path, size, season, episode, ext, transcode, watched,
subtitles[]}`. Two fields matter disproportionately:

- **`transcode`** — the server telling us in advance that this file is not
  browser-native (`media.go:46`), i.e. it will take the HLS path.
- **`size`** — the only bandwidth signal we get, and therefore the entire
  basis of the cellular guard (§5.4).

`subtitles[]` = `{index, lang, label}`. There is no film/show distinction: a
media folder holds one or more files; `season`/`episode` are `0` for a
single-file item.

### 3.4 Playback — the binding constraint

`GET /api/media/{id}/file/{n}` (`playback.go:97`) decides what to serve
**entirely from the file's probed codecs**. No query parameter, header, or
user-agent influences it:

- fresh `.optimized.mp4` sibling exists → serve it, byte-range
- else probed container+codecs are browser-native → serve source, byte-range,
  via `http.ServeContent` (full seek)
- else transcoding enabled → **`307` → `/hls/index.m3u8`**
- else → **`415`**

"Browser-native" = MP4-family + H.264 + AAC/MP3, or WebM/Matroska +
VP8/VP9/AV1 + Opus/Vorbis (`docs/playback.md`).

**The constraint is symmetric, and both halves bind:**

| | native file | non-native file |
|---|---|---|
| want raw bytes | ✅ always | ❌ impossible — 307s to HLS |
| want transcode | ❌ impossible — `/hls/` 415s (`playback.go:153`) | ✅ always |

There is **no quality, bitrate, or resolution parameter** in any playback
handler (verified: no `Query().Get` in `playback.go`). So the server offers
exactly zero playback levers. This is what defeats §5.4's network switch.

HLS is a VOD playlist listing every segment with `#EXT-X-ENDLIST` up front,
backed by one repositionable ffmpeg run **keyed on the file, not on the
viewer** — seeking works, at the cost of a server-side transcode.

**"Per session" was this line's original wording and it was never defined;
M7.6/E-10 defined it.** `internal/server/playback.go` keys the transcode
session as `{media id}/{file index}` with no user and no cookie in it, and
`internal/transcode/hls.go` holds one `run *ffmpegRun` per key, "replaced on a
seek relaunch" (:66). So two people watching the same file share one encoder
and one seek head: whoever seeks past the encode head relaunches it, and the
other one stalls until it comes back. There is no parameter on the route and
nothing this client can do about it — it is recorded so the symptom is
recognisable. `docs/verification-backlog.md` row D and
`tool/spikes/e10_two_clients_one_file.sh`.

Subtitles: `GET .../file/{n}/sub/{k}` returns the k-th **sidecar** converted
SRT→WebVTT per request. Embedded tracks are externalised at import time, not
at play time — so what the server lists is all we can offer via the API.
(libmpv can render embedded tracks itself on the direct-play path; whether to
surface those too is deferred, §11.)

### 3.5 Watch state

`POST /api/media/{id}/progress` with `{file, position, duration, event}` →
`204` (handler `media.go:503`). The rules (`docs/server-api.md`, "Resume
semantics" — transcribed rule by rule from `internal/state/engine.go`) that
`filefin_core` must mirror so the UI never disagrees with the server:

- the resume pointer **never regresses**
- crossing 90% of a file advances the pointer to the next file at 0s
- crossing 90% of the *last* file sets the permanent `watched` flag, and the
  pointer does **not** advance on that same report **when it already resolves
  to that file** — the equal-index branch additionally requires `!crossed`
  (`state/engine.go:81`), so the seconds stay where they were. When the pointer
  is behind or absent, the `targetIdx > curIdx` arm runs instead
  (`state/engine.go:79-80`) and writes `{last file, round(position)}`: index
  **and** seconds move. Verified live — a fresh item
  reporting 95 of 100 comes back with `seconds: 95`. An earlier draft of this
  line stated the first half as though it were unconditional; it is not, and
  `docs/server-api.md`'s "Resume semantics" has the rule stated correctly.
- **the two un-watch operations differ, and the difference is deliberate**
  (`media.go:463` vs `:485`): `POST .../watched {"watched":false}` clears only
  the flag and **keeps** the pointer, so un-watching returns the item to
  *continue where you left off*; `DELETE .../watched` clears the flag **and**
  nils the pointer, so the item leaves every home row. The core exposes these
  as two functions, never one with a boolean.
- an out-of-range file index leaves state **entirely** unchanged, `watched`
  included

Also `DELETE .../progress`, `POST|DELETE .../watched`,
`POST .../favorite` (`{favorite}`), `POST .../rating` (`{rating}`, 1–10, 0
clears).

State is written into `meta.json` in the media folder under a per-user key —
filesystem truth, not cache. It survives a server cache rebuild.

---

## 4. Requirements

### Functional

- **F1.** Add a server by URL; probe `GET /api/state`; report clearly whether
  it is reachable, needs setup, or is not a FileFin server.

  **The probe is a Content-Type and payload check, not a status check.** The
  server registers an SPA catch-all outside its route table
  (`server/server.go:352`), so an unmatched `/api/*` path answers
  `200 text/html` with `index.html` — verified live at v0.20.3. **No path or
  method mismatch is answered with a 404 or a 405**; a handler that did match
  still returns real 404s for an unknown id, which is a different thing. A
  `200` from `GET /api/state`
  therefore proves nothing: any SPA host, any reverse proxy with a fallback,
  and any unrelated web server answers the same way. F1 accepts a server only
  when the response carries `Content-Type: application/json` **and** the body
  decodes to an object with both `needsSetup` and `version`. Anything else —
  including a `200` — is "not a FileFin server". `docs/server-api.md`
  ("Conventions") records the catch-all and the general rule: a non-JSON
  content type on a JSON route is a transport failure, never a payload.
- **F2.** Log in; store both the session and the password in the platform
  secure store, so F3 can re-authenticate silently and indefinitely. The store
  is an injected **port** (`SecretStore`) from M2, with the Keychain/Keystore
  implementation at M7 — `filefin_api` is Flutter-free so `dart test` can run
  it (`docs/architecture.md`, "Why `filefin_api` has no Flutter"). Typing a
  password on a phone every time the server restarts is not acceptable given
  how routine L1 is.
- **F3.** On any `401`, re-authenticate and retry the request **once**
  transparently. Prompt only if re-auth itself fails. (L1 makes this routine.)
- **F4.** Browse the category tree; browse a category as a poster grid; open a
  detail view.
- **F5.** Search with the server's field selector.
- **F6.** Home view: continue / favourites / completed rows.
- **F7.** Play a file with seek, volume, subtitle selection, audio-track
  selection, and next-file advance within a multi-file item.
- **F8.** Resume from `continueIndex`/`continueSeconds`, offering resume vs
  start over.
- **F9.** Report progress on an interval and on pause/seek/completion/close;
  reflect resulting watched/continue changes locally without a full refetch.
- **F10.** Toggle favourite, set rating, mark/clear watched.
- **F11.** Switch between saved servers. The *mechanism* lands at M2 — one
  client per `ServerId`, each with its own cookie jar, secret namespace and
  certificate pin — and the switching UI at M7 (§10).
- **F12.** Explain playback refusals in the user's terms. A `415` means
  "transcoding is disabled on the server and this file needs it" — name that,
  never "playback failed".

  **Which 415, precisely.** §3.4's table has two, and only one can reach this
  client: `GET .../file/{n}` answers `415 transcoding disabled` for a file that
  needs transcoding on a server where it is off, and that is F12's. The hls
  route's `415 not transcodable` is the symmetric half and is **unreachable
  from here**, because `PlaybackRequest.url` is always the file route and
  libmpv follows the `307` itself. Both are captured in `error_shapes.txt`;
  `docs/server-api.md` carries the table. Widening F12's wording to cover both
  would describe a case that cannot arrive.

  **It is answered before the engine opens, not after it fails.** libmpv
  surfaces no status code — measured at M5.0/E-I, a 415 reaches the player as
  `Failed to open <url>.` over a black surface and nothing else — so
  `PlayerController` asks `requirePlayable` first, guarded on
  `fileInfo.transcode`, which stays `true` on a server that will not honour it
  (M5.0/E-B).
- **F13.** Cellular guard: before playing over a metered connection, if the
  file exceeds a configurable size threshold, warn with the actual size and
  require confirmation. Per-server "wifi only" setting. (§5.4)
- **F14.** Background audio and lock-screen transport controls. (R3; **R2's
  PiP is declined**, §8 and §11.)

  **Two halves with very different verifiability, and the split is the design.**
  Everything up to `NowPlayingHost` is ours and is gated: what is published on
  open and on a file advance, what a remote button does to the player, and that
  the Android manifest and the iOS plist carry what E-6 measured they need.
  Whether the OS then drew a control, and whether a sound came out of a
  backgrounded phone, has no headless representation at all —
  `docs/verification-backlog.md` rows L, M and N, each with the procedure.
- **F15.** Trust-on-first-use TLS. When a server's certificate is not trusted
  by the OS (self-signed or private CA — the common case for self-hosted),
  show its SHA-256 fingerprint, let the user accept it, and **pin** it. A
  later fingerprint change is a loud, blocking warning, not a silent
  re-accept. Plain `http://` is permitted for LAN servers but flagged
  visibly at F1, because credentials cross the network in the clear.

### Non-functional

- **NF1.** Cold start to a usable library view under 2s on a warm cache.
- **NF2.** Poster grid scrolls at 60fps over a 5000-item category. L2 means
  the whole array arrives at once — the list must be virtualised and posters
  lazily fetched.
- **NF3.** Seek responds within 500ms on direct play.
- **NF4.** No credential reaches a log, a `toString()`, or unencrypted
  storage (CLAUDE.md §9).
- **NF5.** Every request has a timeout, and every in-flight **read** is
  cancellable. A hung server never hangs the UI.

  **A write in flight is deliberately allowed to finish, and the M7.9 audit is
  what corrected this line.** It said "every in-flight operation", which five
  call sites contradict — the four F10 writes in `browse/watch_actions.dart`
  and `playback/progress_reporter.dart`'s report. Every one of them is right
  and the sentence was wrong. Cancelling a `POST` that has already gone leaves
  the server's state unknown to a client whose whole optimistic-update design
  (F9, F10) is keyed on the write's answer; and `PlayerController.dispose`
  fires the final `stop` report **and** cancels its `CancelToken` in the same
  method, so a reporter sharing that token would cancel the one report NF6
  exists to make. The port still takes a `CancelToken` on every method
  (`library_api.dart:20`) — the capability is uniform, the *use* is not, and it
  is the reads that use it.
- **NF6.** Playback survives app backgrounding and returns to the same
  position.

### Constraints

- **C1.** Flutter + Dart; Android and iOS only.
- **C2.** Playback via `media_kit`/libmpv — one engine, one set of behaviours
  on both platforms.
- **C3.** No modified FileFin server is required for the baseline feature set.
  Anything upstream-dependent is additive, probed at runtime, and degrades
  cleanly.
- **C4.** Read-only against the library. No `/api/admin/*` route is called.
- **C5.** Minimum OS: **Android 8 (API 26)** and **iOS 15**. Comfortably
  within `media_kit` support, gives modern PiP and media-session APIs, keeps
  the CI matrix small.
- **C6.** Distribution is **direct APK** and **TestFlight/sideload**. No app
  store submission, so no store review gate on the release path. F-Droid is an
  aspiration, not a commitment (R4).

---

## 5. Architecture

### 5.1 Layers

```
┌─────────────────────────────────────────────┐
│ apps/mobile                                 │  Flutter UI, media_kit player,
│                                             │  secure storage, connectivity
├─────────────────────────────────────────────┤
│ filefin_api      (dio + cookie jar)         │  auth, 401-retry (F3),
│                                             │  typed endpoints, TLS pinning
├─────────────────────────────────────────────┤
│ filefin_core     (pure Dart, no I/O)        │  models, extension-type IDs,
│                                             │  URL building, resume rules,
│                                             │  playback decision
└─────────────────────────────────────────────┘
```

`filefin_core` is pure (CLAUDE.md §6): it is where the server's progress
semantics are re-implemented and property-tested, so optimistic UI updates
provably match what the server will do.

`filefin_api` owns the cookie jar and is the **only** place a `401` is
interpreted, so F3 exists once rather than at every call site.

### 5.2 Repository layout

```
packages/
  filefin_core/     pure Dart: models, rules, URLs
  filefin_api/      HTTP client
apps/
  mobile/           Flutter app
docs/
  server-api.md     endpoint contract, cited + version-pinned (§8)
  architecture.md
  risks.md          open risks and their spikes
test/fixtures/      captured real server payloads
tool/               gate scripts
```

### 5.3 Streaming and authentication

The neat consequence of the native stack: `Media` accepts `httpHeaders`, so
the session cookie is handed directly to libmpv.

```dart
Media(streamUrl, httpHeaders: {'Cookie': 'filefin_session=$token'})
```

No local proxy, no custom URI scheme, no CORS shim — the entire layer a
webview client would need does not exist here.

**Verified (R1, 2026-08-08).** libmpv preserves the `Cookie` header across the
`307` to the HLS playlist and onto segment requests — confirmed empirically
against a real seeded server via FFmpeg's libavformat, the same HTTP/HLS stack
libmpv embeds, with a negative control that failed as required (§8 R1). One
`httpHeaders` map therefore covers both playback paths.

### 5.4 Playback decision — a guard, not a switch

The intent was to direct-play on wifi and transcode on cellular. **§3.4 makes
that impossible**: the server picks the mode from codecs alone, and neither
half can be overridden. What we can actually vary is *whether we start
playback at all*, using `fileInfo.size` — the only bandwidth signal available.

So the decision lives in `filefin_core` as one pure function:

```dart
PlaybackDecision decide(FileInfo file, NetworkType net, PlaybackSettings s)
//  → PlayDirect | PlayHls | ConfirmLargeOnMetered(bytes) | Refuse(reason)
```

Deterministic, no I/O, exhaustively unit-tested. Today it has exactly one
lever (the metered-connection guard, F13). It is written as a decision
function rather than an `if` at the call site so that if the server ever gains
quality selection, the new branch lands in a tested pure function instead of
being retrofitted into the player.

Per CLAUDE.md §1, branches for levers the server does not have are **not**
written until it has them.

---

## 6. Technology decisions

| Decision | Choice | Why |
|---|---|---|
| Framework | Flutter | §2 |
| Player | `media_kit` (libmpv) | Plays MKV/HEVC/DTS identically on both platforms; prebuilt libs |
| HTTP | `dio` + `dio_cookie_manager` | Interceptors are the natural home for F3's 401-retry |
| Models | `freezed` + `json_serializable` | Sealed unions for decisions; tolerant decode (§8) |
| Secrets | `flutter_secure_storage` | Keychain / Keystore (§9); holds session **and** password (F2) |
| TLS | a custom `HttpClient.connectionFactory` that owns the handshake **plus** per-response certificate validation, over a pinned fingerprint store | F15; must be in the `dio` setup from M2, not retrofitted. **Both hooks are required**, and `badCertificateCallback` is not one of them — it is handed the CA, not the leaf. See §8 R5 |
| Settings | plain JSON in app support dir, no secrets | inspectable |
| Network type | `connectivity_plus` | F13's metered check |
| OS floor | Android 8 (API 26), iOS 15 | C5 |
| State | Hand-written `ChangeNotifier` + one `AsyncController<T>` + one `InheritedWidget`; **no state package** | Decided at M3 against real screens, not in the abstract. D9, and `docs/architecture.md`'s D-Q1 carries the reasoning and the retirement condition |
| Testing | `test`, `mutation_test`, real-server harness | Mocks hide exactly the failures that matter |

---

## 7. Data model (client-side)

Nothing durable but settings and credentials. Specifically **no local mirror of
the library**: L2 means responses can be large, but the server is the truth and
a stale mirror is worse than a refetch.

```
settings.json      servers[] { id, name, baseUrl, lastUser, wifiOnly,
                               allowUnverifiedPlayback }
                   selectedServerId
                   playback { progressIntervalSecs, meteredWarnBytes }
secure store       filefin/{serverId}/session   → cookie value
                   filefin/{serverId}/password  → for silent re-auth (F2)
                   filefin/{serverId}/certpin   → accepted SHA-256 (F15)
```

**Three lines that used to be here are gone, and the M7.9 audit is why each of
them went** — a spec that lists what does not exist is worse than one that is
short, because a reader cannot tell the two apart.

- **`allowUnverifiedPlayback` was BUILT and never written down.** It is D10 and
  it arrived at M4; §7 had said five fields since M0.
- **`selectedServerId` arrived at M7.3** with F2's cold start and F11's picker.
- **`ui { theme, subtitleLanguage }` was never built and, until M7.9, was
  nowhere recorded as dropped** — not in §11, not in §13, not in `STATE.md`,
  not in the backlog. It is now **deferred, in §11, with a reason**.
- **`cache/posters/` was never built either**, and that one *was* recorded, in
  `browse/poster_image_provider.dart` and `STATE.md`. It is in §11 now so the
  record is where a reader looks first. What was NOT true anywhere is §5.1's
  diagram and `docs/architecture.md`'s, which both said `filefin_api` holds a
  poster cache. It never did; both are corrected.

---

## 8. Risks to retire early

Each gets a spike before the milestone that depends on it. Tracked in
`docs/risks.md`; none is assumed resolved.

- **R1 — Headers across redirect. ✅ RETIRED 2026-08-08.** libmpv embeds
  FFmpeg's libavformat for HTTP and HLS, so ffmpeg exercises the same code
  path. Against a real seeded server, `ffmpeg -headers 'Cookie: …' -i
  .../file/0` on an HEVC item followed the `307`, fetched the playlist and
  segments, and decoded — exit 0. The negative control without the cookie
  failed with `401 Unauthorized` (exit 8), so the test could fail and did.
  Byte-level confirmation: playlist `200`, `seg0.ts` `200 video/mp2t`.

  Conclusion: `Media(httpHeaders: {'Cookie': …})` is sufficient for both
  playback paths. §5.3's assumption holds and M5 needs no alternative design.
  Harness: `tool/spikes/r1_headers_across_redirect.sh`.
- **R5 — The `filefin` binary has no TLS listener.** Verified at v0.20.3: no
  `ListenAndServeTLS`, no certificate flag, nothing TLS-shaped anywhere in
  `internal/` or `cmd/`. TLS is a reverse-proxy concern upstream. So M2's exit
  criterion "a self-signed server connects only after explicit accept" is met
  against a Dart `HttpServer.bindSecure` with committed test certificates — a
  real handshake, just not a real FileFin. SPEC §6's TLS row also understated
  F15 **twice**: `badCertificateCallback` alone is not enough, because dart:io
  does not call it for an OS-trusted certificate, so a server pinned while
  self-signed that later gets a CA certificate would change fingerprint with the
  callback never firing — and, worse, that hook is handed **the certificate at
  which chain verification failed**, which on a real `[leaf, CA]` chain is the
  CA. A private CA is F15's stated common case, and against one the pin was
  compared against the CA, the trust-on-first-use prompt named the CA, and an
  impostor holding any other certificate from that CA received the session
  cookie. The row now names `HttpClient.connectionFactory`, which is the only
  hook that sees the leaf before a request byte is written. `docs/risks.md`
  carries the full measurement, before and after, in bytes.
- **R2 — iOS Picture-in-Picture. ❌ DECLINED 2026-08-10, not retired.** Spiked
  at M7.6/E-7 as a static read, because the answer is decided by what is
  `private`. `media_kit_video` 2.0.1's decoded frame **is** a 32BGRA
  `CVPixelBuffer` and `copyPixelBuffer()` is public — but `VideoOutput.texture`,
  `VideoOutputManager.videoOutputs` and `MediaKitVideoPlugin.videoOutputManager`
  are all private, and the package's only public entry point is
  `register(with:)`. No instance of the texture is reachable, so PiP needs a
  **fork**, plus a `CMSampleBuffer` timing layer and a contest with Flutter over
  a three-deep buffer pool. PiP is not in F14's wording and §10's M7 row is
  corrected to match. Harness: `tool/spikes/e7_ios_pip_reachability.sh`, which
  asserts all seven facts in their own direction and was seen to fail.
- **R3 — Lock-screen / MediaSession controls. ⚠️ PARTLY RETIRED 2026-08-10.**
  Spiked at M7.6/E-6 against a scratch app on a real Android emulator and the
  iOS simulator, five arms. What it cost: `audio_service` on Android and one
  `Info.plist` key on iOS. What it found first was **a client default rather
  than an OS behaviour** — `Video.pauseUponEnteringBackgroundMode` defaults to
  `true` and pauses the player itself, which every arm reads as "backgrounding
  stops playback" until it is turned off. With it off, Android decodes 1:1 with
  the wall clock for a full minute backgrounded and the OS **mutes** it
  (`mutedState:opControlAudio`) unless a foreground service and a `MediaSession`
  are running; iOS suspends the process without `UIBackgroundModes: audio` and
  does not with it, and libmpv sets `AVAudioSessionCategoryPlayback` itself.
  **Not retired**, because the shipped iOS libmpv's *audibility* and Android's
  behaviour under Doze are device-only — `docs/verification-backlog.md` rows L
  and M. Harness: `tool/spikes/e6_background_playback.sh`.
- **R4 — F-Droid and prebuilt binaries.** C6 removes the App Store, which
  defuses the mpv GPL/LGPL question that would otherwise have been a hard
  blocker. It does not defuse F-Droid: their inclusion policy requires
  building everything from source in their buildserver, and `media_kit_libs_*`
  ships **prebuilt** libmpv binaries. F-Droid would therefore likely reject
  the app as-is, and building libmpv from source in their pipeline is
  substantial work.

  Consequence: F-Droid is explicitly *not* a commitment (C6). Direct APK is
  the Android release path and has no such constraint. Downgraded from
  blocking to advisory — spike it only if F-Droid becomes a real requirement.
  Licensing still gets checked once in M0 and recorded, because "we never
  looked" is not an answer worth carrying.

---

## 9. Testing

- **Unit** — `filefin_core` rules, deterministic, injected time, no I/O.
- **Property** — the §3.5 resume engine: pointer monotonicity, the 90%
  threshold, watched-clear semantics. These are invariants the *server*
  enforces; if our model disagrees, the UI lies to the user.
- **Contract** — every model round-trips a captured real payload from
  `test/fixtures/` (CLAUDE.md §8), plus a tolerance test proving an unknown
  extra field decodes cleanly.
- **Integration** (`just it`) — against a real `filefin` binary over a seeded
  temp data dir: login; **session-loss recovery** (restart the server
  mid-test, assert F3 recovers silently); byte-range seek; the 307→HLS path
  including R1; the 415 path and F12's message.
- **Widget/golden** — player controls and the poster grid. **There are no
  golden tests, and that is a decision taken at M3 rather than an omission.** A
  committed golden PNG is stable only for one platform and one engine revision;
  this repository develops on macOS/arm64 and CI runs `ubuntu-latest`, so a
  golden goes red on whichever machine did not generate it — and CLAUDE.md
  forbids skipping a test to hide that. M3 asserts **layout** instead
  (`tester.getSize`, `getTopLeft`, exact indentation arithmetic, widget counts)
  plus `androidTapTargetGuideline`, `iOSTapTargetGuideline` and
  `textContrastGuideline`, all of which are platform-stable — and one
  `RenderFlex overflowed` was in fact caught that way. Nothing verifies pixels;
  `docs/verification-backlog.md` row 9 carries the experiment (choose one
  canonical platform and generate there) and what it costs to be without it.
- **E2E** — add server → log in → browse → play 5s → assert progress landed in
  `meta.json` on disk.

---

## 10. Milestones

| M | Deliverable | Exit criterion |
|---|---|---|
| **M0** | Workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture; spike **R1**; record the mpv licensing position (R4) | `just check` exits 0; every gate *seen to fail* |
| **M1** | `filefin_core`: models, extension-type IDs, URL building, resume engine, `decide()` | property tests green; purity gate passes |
| **M2** | `filefin_api`: login, secure-store session+password, F3 retry, browse endpoints, **TLS pinning (F15)** | `just check` exits 0 **and** `just it` exits 0 on a machine with the binary: the integration suite survives a mid-test server restart; a self-signed server connects only after explicit accept, and a changed fingerprint blocks. **The TLS half is met against a Dart `HttpServer.bindSecure`, not against `filefin`** — the binary has no TLS listener at all (§8 R5) |
| **M3** | App shell + browsing UI: tree, virtualised grid, detail (F4) | 5000-item category scrolls at 60fps (NF2) — **met by proxy, and the proxy is named.** 60fps cannot be measured headlessly: `flutter test` runs `flutter_tester` under a fake clock with no vsync and no rasterizer, and `flutter_tools` demands a connected device for anything under `integration_test/` (both measured at M3.0/M3.7). What IS gated is the property 60fps rests on — a bounded live-tile count at the top, middle and end of a 5000-item grid; poster requests far below the item count and never above the tiles ever built; the listing fetched exactly once; a scrolled-away tile cancelling. A build+layout wall-clock number is printed and deliberately NOT gated. Real frame timing is `docs/verification-backlog.md` row 1 |
| **M4** | Playback, direct path (F7, F8, F9) + cellular guard (F13) | **Met, and the criterion's "where the server allows" turned out to be load-bearing.** An MKV plays via direct bytes exactly when the cache row has been probed: `fileNeedsTranscode` (`internal/server/playback.go:78`) consults the probed container and codecs only under `f.Container != "" && f.VideoCodec != ""` and otherwise falls back to `transcode.NeedsTranscode(f.Ext)`, whose direct-play set is `{.mp4, .webm, .m4v}`. `tool/testserver/seed.sh` rebuilds the cache and never probes, so every seeded row has empty format columns and every verdict taken from the seeded library is that fallback. `tool/spikes/e5_mkv_direct_play.sh` runs both arms over one VP9/Opus `.mkv`: unprobed → `transcode:true`, **307 to HLS**; after `POST /api/admin/probe/scan` fills the row with `matroska,webm` / `vp9` / `opus` → `transcode:false`, **200 with `Accept-Ranges: bytes`** and `Content-Type: video/x-matroska`. §3.4 is therefore correct as written. **An earlier draft of this row said the criterion was unsatisfiable and that the extension decides — that was arm 1 read as the rule, and it is corrected here rather than quietly dropped.** The gated half is the seeded H.264 MP4, which plays end to end under `just it` with resume, progress reporting, subtitle and audio selection and the cellular guard; the MKV half is the spike, because seeding a permanently probed item churns the category fixtures for no new client behaviour (STATE.md's M4 section says so) |
| **M5** | HLS path + F12 messaging | **Met, and playback itself needed no client change at all** — `PlaybackRequest.url` was already `api.fileUrl(...)`, libmpv follows the `307` and decodes the HLS the server produces, so M5 is one error variant, one bounded pre-flight, one `if`, one panel and the tests. Measured end to end under `just it`: the seeded HEVC show plays through the `307` with mpv reporting the playlist's own `3.023 s`, an audio track, a resume offset honoured on a VOD playlist (`Media(start:)` works — nothing had ever tested it), a **backwards** seek, and completion within 500 ms of the duration with the counters reset immediately before. Against a `transcodeEnabled: false` server a real `PlayerController` names transcoding as the cause and **never opens the engine**. The 415 a client can receive is the **file** route's `transcoding disabled`; the hls route's `not transcodable` is unreachable from here (F12) |
| **M6** | Search, home rows, favourite/rating/watched (F5, F6, F10) | `just check` 0 AND `just it` 0. The POST/DELETE watched distinction proven **behaviourally against the real binary in both directions**: after `POST {"watched":false}` the item is back in `continue` with its pointer intact and the detail offers *Continue*; after `DELETE` it is in no row and offers *Play*. Search exercised live for every field the client can send, including both numeric scopes' fail-closed behaviour. Home rows and search results virtualised on M3's NF2 proxies over a 5000-item list. **MET.** `just check` and `just it` both exit 0 (86 integration tests, floors 56 / 30). The distinction is proven on the detail screen and, from M6.8, against the real binary in `watch_state_test.dart` — six ordered steps, `POST {"watched":false}` returning the item to `continue` at 0:45 and `DELETE` leaving it in no row at `0/0`, each compared against `applyWatchState`'s prediction. `search_test.dart` exercises all eleven fields live plus both numeric scopes' fail-closed behaviour. Home rows and search results are virtualised on M3's NF2 proxies — a bounded live-widget count and a `SliverChildBuilderDelegate` over 500 and 2000 items — which is the same evidence F4's grid has and, like it, not a frame-timing measurement (backlog row 1) |
| **M7** | Multi-server + secure storage (F11); background audio and lock-screen controls (F14) after R2/R3; the full-spec audit | **MET.** `just check` 0 and `just it` 0 on a machine with the binary. F2's persistence half is a `flutter_secure_storage` decorator over the in-memory cache, namespaced per `ServerId` and proven not to leak between two of them; a cold start restores a session and, when the server has forgotten it, F3 renews from the stored password with no prompt — proven against the real binary, and against **two** real binaries with two accounts. F11's picker adds, switches and removes, and removal deletes all three secrets before it touches `settings.json`. **F15's accept-and-pin loop reached the app for the first time** — until M7.5 `main.dart` never passed `pin:` and `SecretKind.certificatePin` had no production reader or writer, which no document had recorded. F14 is background audio and a lock-screen transport behind a `NowPlayingHost` port, with `audio_service` on the far side of it; **PiP is dropped from this row** because R2 declined it and F14 never asked for it. What no host can close is in `docs/verification-backlog.md` rows J, K, L, M and N, each with its procedure |
| **M8+** | Optional: direct-play capability probe + upstream PR; offline downloads | |

---

## 11. Deferred

- **A UI theme setting, and a preferred subtitle language.** §7 listed
  `ui { theme, subtitleLanguage }` from M0 and no milestone ever built either;
  the M7.9 audit found neither recorded as dropped anywhere, which is how a gap
  survives seven milestones. Both are dropped **as decisions** rather than
  discovered again:
  - *theme* — no F-requirement asks for one. The app seeds a single `ThemeData`
    and `app.dart` hard-codes it. Building the setting is a settings row, a
    `ThemeMode` in `settings.json` and a `MaterialApp.themeMode`, which is
    small; what it is not is anything M7 needs (§1). **Its retirement condition
    is a user asking for it**, and the honest statement of the cost of not
    having it is that the app is light in a dark room.
  - *subtitleLanguage* — the identifier's only occurrence in the whole tree was
    this spec. Subtitle selection is manual and session-scoped
    (`player_controls.dart`), and `PlayerController._open` already applies a
    default: the first sidecar the server lists. A language preference would
    change that default to a match against `SubtitleInfo.lang`, which is real
    but is F7 gold-plating rather than F7. **Its retirement condition is a
    second sidecar language appearing in a real library** — one language is one
    choice, and a preference between one thing is not a preference. The commit
    that deferred both claimed "each" had a condition and this one did not;
    M7.R is where the claim was made true rather than repeated.
- **`cache/posters/`, the LRU disk cache.** Dropped at M3 and recorded then in
  `browse/poster_image_provider.dart` and `STATE.md`; recorded HERE at M7.9 so
  §7 and §11 agree. Flutter's in-memory `ImageCache` bounds the problem the
  disk cache existed for; whether it really does over a 5000-item library with
  real bytes is `docs/verification-backlog.md` row 7, which is the condition
  that would un-defer it.
- **iOS Picture-in-Picture (R2).** Declined at M7.6 with the measurement that
  declined it — `media_kit_video` seals every route to the decoded frame, so
  PiP needs a fork. It was never in F14's wording; it appeared only in §10's M7
  row, which is corrected. `docs/risks.md` R2 carries the seven facts and
  `tool/spikes/e7_ios_pip_reachability.sh` re-checks them.
- **F10's revert reinstates the detail captured at TAP time, so it can undo a
  playback fold.** Carried from M6 into this list at M7.8 rather than left in
  `STATE.md`, because a released project stops reading a milestone log. When a
  watch write fails, `WatchActions` puts back field-for-field what was on
  screen when the user tapped — which is asserted by test and is what makes the
  revert predictable — so a progress report that landed in between is undone
  with it. Closing it means giving `WatchActions` a reader for the
  currently-published detail and changing the revert to "the inverse state
  applied to whatever is on screen now", which is a design change with its own
  trade-offs on a feature that is otherwise correct.
- **The reload a back gesture triggers can overtake the write that caused it.**
  Same treatment, same reason. `wroteOrWriting` (`browse/watch_actions.dart`)
  is strictly better than what it replaced and its own doc names the residual:
  the detail route can pop while a write is still in flight, and the home rows
  then re-read state the server has not stored yet. Closing it means holding
  the back gesture until the write answers, which is a worse trade for the
  person holding the phone.
- Offline downloads and a download queue.
- Embedded **subtitle** tracks libmpv can see but the API does not list.
  **Embedded AUDIO is no longer deferred — it is used, because nothing else can
  satisfy F7.** `fileInfo` carries `subtitles[]` and no audio array at all
  (§3.3), so libmpv's own track list is the only possible source for
  audio-track selection. `PlaybackHost.tracks` therefore reports audio and
  nothing else, and `MediaKitPlaybackHost` drops mpv's synthetic `auto`/`no`
  pseudo-entries so a two-track file does not read as four.
- Chromecast / AirPlay.
- Any admin surface (N1).
- Desktop (N3), Flutter Web (N5).
- MyDramaList / MyAnimeList profile sync (`/api/mdl/*`, `/api/mal/*` exist).
- Trickplay scrubbing — the server has a thumbnail agent but no endpoint
  serving a sprite sheet.

---

## 12. Upstream contributions

Optional, additive, runtime-probed (C3). The client must remain fully
functional against a stock server.

1. **`?direct=1`** — force raw bytes for a non-native file, letting libmpv
   decode locally and the server skip transcoding entirely. Small, well-scoped,
   and the natural payoff of C2. Highest value on LAN.
2. **Quality selection on HLS** — allow transcoding a file that does *not*
   need it, plus a bitrate parameter, so the cellular half of §5.4 becomes
   implementable. This is substantially bigger — effectively a transcode
   ladder — and may reasonably be declined.

Neither is on the critical path. Both are recorded so the constraint is
documented rather than rediscovered.

---

## 13. Decisions taken

Recorded so they are not silently relitigated. A decision reversed here must
be reversed *here first*, then in the sections it touches.

**This table is the index.** A decision whose argument does not fit a row has a
file in [`docs/decisions/`](docs/decisions/), linked from its row, and the code
cites the number rather than repeating the argument (CLAUDE.md §2). Numbers are
never reused. How the server and our dependencies were *observed* to behave is
not a decision and lives in [`docs/field-notes.md`](docs/field-notes.md).

| # | Decision | Rationale | Touches |
|---|---|---|---|
| D1 | Flutter + Dart, not Tauri v2 | Tauri mobile hands playback to a fullscreen native Activity, so the player UI would be native anyway (§2) | whole spec |
| D2 | `media_kit`/libmpv, not per-platform players | AVPlayer cannot play MKV, so iOS needs a libmpv-class engine regardless; one engine = one set of behaviours (§2) | C2, §6 |
| D3 | Mobile only; desktop dropped | Stated priority | N3 |
| D4 | Network-adaptive playback is a **guard**, not a switch | The server exposes no playback levers in either direction (§3.4) | L3, §5.4, F13 |
| D5 | Password stored in the platform secure store | L1 makes 401s routine; re-typing a password on a phone each time is unacceptable | F2, §7 |
| D6 | Trust-on-first-use with certificate pinning | Self-hosted servers commonly use self-signed or private-CA certs | F15, M2 |
| D7 | Android 8 / iOS 15 floor | Within `media_kit` support, modern PiP and media-session APIs, small CI matrix | C5 |
| D8 | Direct APK + TestFlight/sideload; no app store | Removes store review from the release path, and defuses the mpv GPL blocker | C6, R4 |
| D9 | App state is a hand-written `ChangeNotifier` plus one generic `AsyncController<T>`, `AsyncView<T>` and `InheritedWidget`. No state-management package | M3's real screens are three, each one fetch, one cancel-on-dispose, one error render. A framework's rent at that size is unpaid surface (§1, §5) — and, less obviously, it would SHRINK what `just mutants` reaches, because framework-internal branching is never in our diff. Retirement condition at M7 in `docs/architecture.md` | §6, M3 |
| D10 | **TLS playback is a per-server choice that DEFAULTS TO REFUSE** | libmpv verifies no certificate by default — measured both directions at M4.0 (`docs/risks.md` R6) — so F15's pin does not reach the playback socket. `plainHttp` plays, `osTrustedTls` plays with `tls-verify=yes`, `pinnedTls` is refused unless `SavedServer.allowUnverifiedPlayback` is on, and when it is on a **persistent banner** names exactly what is unprotected: the session cookie may reach a peer whose certificate was never checked | F15, §5.3, `decide()`, M4 |
| D11 | **CLAUDE.md §13 — "no backward compatibility before release" — retires at the first TAGGED RELEASE, and M7 is the last milestone that may change a stored format freely** | The condition was "the first release", which is a date nobody can look up mid-milestone. M7.3 and M7.4 both changed `settings.json` (`selectedServerId`, and `servers[]` gaining a sixth field at M4), and retiring the rule *inside* M7 would have put a migration burden on M7's own steps for installs that do not exist. Whoever cuts the tag owns the switch: from that commit on, a change to `settings.json`, to the secure-store key layout, or to any cache schema needs a migration and a lenient decoder, and `SettingsStore`'s deliberate discard-on-mismatch (`servers/settings.dart`) becomes a defect rather than a design | CLAUDE.md §13, §7, `SettingsStore`, `SecretStore` |
| D12 | dio is configured `ResponseType.plain`, so decoding stays in `filefin_api` | dio's default hands us two decisions that are ours: whether the media type is acceptable (F1's whole mechanism) and what a bad body means. → [`D12`](docs/decisions/D12-plain-response-type.md) | `transport.dart`, F1 |
| D13 | **dio never follows a redirect** | The pinner only sees the final connection, so a followed `302 → http://impostor` returned an attacker's payload as the pinned server's answer (measured, M2). → [`D13`](docs/decisions/D13-no-redirect-following.md) | `transport.dart`, F15 |
| D14 | Every list is virtualised | Nothing paginates (L2), so the whole array arrives at once and the only lever left is per-frame cost. → [`D14`](docs/decisions/D14-virtualised-lists.md) | NF2, `media_grid.dart`, `visible_rows.dart` |
| D15 | `continueIndex 0 / continueSeconds 0` is read as "no pointer" | The payload carries the derived view, never the stored pointer, so `0`/`0` is ambiguous. A tie-break with a residual divergence that persists. → [`D15`](docs/decisions/D15-resume-pointer-from-derived-view.md) | F8, F9, `watch_state.dart` |
| D16 | Watch state mirrors the server verbatim, including values its write path would reject | The server validates rating on write, not on read; normalising on read lost data (M6.R/P1.4). → [`D16`](docs/decisions/D16-mirror-server-state-verbatim.md) | F10, `watch_state.dart` |
| D17 | F10's four writes are applied to the screen before the server answers | Waiting is unusable over cellular, and the prediction is *exact* because all four are total assignments in the server's own fold. → [`D17`](docs/decisions/D17-optimistic-watch-state-writes.md) | F10, `watch_actions.dart` |
| D18 | Every route is one full string literal, never assembled | `undocumented_endpoint` (§8) greps literals and cannot reconstruct an interpolated path. → [`D18`](docs/decisions/D18-one-path-literal-per-route.md) | §8, `urls.dart` |
| D19 | Pinning owns the handshake, through two hooks, over one pure policy | `badCertificateCallback` is handed the CA rather than the leaf, so a private-CA deployment pinned the wrong certificate (measured, M2). → [`D19`](docs/decisions/D19-certificate-pinning-wiring.md) | F15, D6 |
| D20 | The 401 retry lives in one interceptor, bounded by three separate mechanisms | Sessions die with the process, so a 401 is routine; two copies of the retry would disagree about when to stop. → [`D20`](docs/decisions/D20-401-retry-lives-in-one-interceptor.md) | F3, §5.1 |
| D21 | The HTML refusal applies to 2xx responses we intend to decode, and nowhere else | Both obvious generalisations break something: "must be JSON" refuses working responses, and applying it to errors would hide every 401 from F3. → [`D21`](docs/decisions/D21-html-refusal-on-2xx-only.md) | F1, F3 |
| D22 | Every port is an `abstract base class`, never an interface | `base` forces `extend`, which makes a new method a compile error everywhere and `SecretStore`'s redacting `toString` inherited rather than merely recommended. → [`D22`](docs/decisions/D22-ports-are-abstract-base-classes.md) | §9, all four ports |
| D24 | The player verifies against the device's store where it can, and shipped roots where it cannot | Both shipped players link mbedTLS and have no system trust store; iOS has no API to enumerate one, so it gets Mozilla's roots in the app. The player's trust then diverges from the API client's on iOS, which is the cost. → [`D24`](docs/decisions/D24-player-trust-store.md) | F15, D10, `ca_bundle.dart` |
| D23 | The controller advances files itself, and every report is gated on the engine agreeing | libmpv is a second source of truth for the fact every report is keyed on; three separate mechanisms keep them from disagreeing, each added after the previous proved insufficient. → [`D23`](docs/decisions/D23-the-engine-owns-one-file-at-a-time.md) | F7, F9, `player_controller.dart` |

### Still open

Nothing. Q1 was the last entry and became D9 at M3.
