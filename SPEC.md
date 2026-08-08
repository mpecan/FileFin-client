# FileFin Client — Technical Specification

A mobile client for [FileFin](https://github.com/xuedi/FileFin), a
filesystem-first self-hosted media server (Go backend, Svelte web UI, EUPL
v1.2).

**Status:** M0, M1 and M2 complete, M3 next. The workspace, every quality gate, the
git hooks and CI exist; `docs/server-api.md` records the contract and
`test/fixtures/` holds captured real payloads. `packages/filefin_core` holds
the wire models, the extension-type IDs, URL construction, the resume engine and
`decide()` — pure Dart, no I/O. `packages/filefin_api` holds the HTTP client:
typed endpoints, the cookie jar, F3's transparent 401 retry and F15's
certificate pinning, with `just it` running it against a real `filefin` binary.
`STATE.md` is the milestone-by-milestone record.

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
| `GET /api/home` | `{continue, favorites, completed}`, each `MediaSummary[]`, newest-first |
| `GET /api/search?q=&field=` | `MediaSummary[]`; `field` ∈ all/title/cast/genre/director/language/year |
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
backed by one repositionable ffmpeg run per session — seeking works, at the
cost of a server-side transcode.

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
- **F13.** Cellular guard: before playing over a metered connection, if the
  file exceeds a configurable size threshold, warn with the actual size and
  require confirmation. Per-server "wifi only" setting. (§5.4)
- **F14.** Background audio and lock-screen transport controls. (R2/R3)
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
- **NF5.** Every request has a timeout; every in-flight operation is
  cancellable. A hung server never hangs the UI.
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
│                                             │  typed endpoints, poster cache
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
| State | Decided at M3, recorded in `docs/architecture.md` | Not chosen speculatively (§1) |
| Testing | `test`, `mutation_test`, real-server harness | Mocks hide exactly the failures that matter |

---

## 7. Data model (client-side)

Nothing durable but settings, credentials, and a poster cache. Specifically
**no local mirror of the library**: L2 means responses can be large, but the
server is the truth and a stale mirror is worse than a refetch.

```
settings.json      servers[] { id, name, baseUrl, lastUser, wifiOnly }
                   ui { theme, subtitleLanguage }
                   playback { progressIntervalSecs, meteredWarnBytes }
secure store       filefin/{serverId}/session   → cookie value
                   filefin/{serverId}/password  → for silent re-auth (F2)
                   filefin/{serverId}/certpin   → accepted SHA-256 (F15)
cache/posters/     content-addressed, LRU-bounded
```

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
- **R2 — iOS Picture-in-Picture.** iOS PiP is built around `AVPlayerLayer` /
  `AVSampleBufferDisplayLayer`; libmpv renders its own surface. PiP may be
  unavailable or need custom platform work. Affects F14. *Spike before M7.*
- **R3 — Lock-screen / MediaSession controls.** `media_kit` is a playback
  engine, not a media-session integration. Establish what F14 actually costs
  on each platform. *Spike before M7.*
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
- **Widget/golden** — player controls and the poster grid.
- **E2E** — add server → log in → browse → play 5s → assert progress landed in
  `meta.json` on disk.

---

## 10. Milestones

| M | Deliverable | Exit criterion |
|---|---|---|
| **M0** | Workspace, gates, hooks, CI, `docs/server-api.md`, fixture capture; spike **R1**; record the mpv licensing position (R4) | `just check` exits 0; every gate *seen to fail* |
| **M1** | `filefin_core`: models, extension-type IDs, URL building, resume engine, `decide()` | property tests green; purity gate passes |
| **M2** | `filefin_api`: login, secure-store session+password, F3 retry, browse endpoints, **TLS pinning (F15)** | `just check` exits 0 **and** `just it` exits 0 on a machine with the binary: the integration suite survives a mid-test server restart; a self-signed server connects only after explicit accept, and a changed fingerprint blocks. **The TLS half is met against a Dart `HttpServer.bindSecure`, not against `filefin`** — the binary has no TLS listener at all (§8 R5) |
| **M3** | App shell + browsing UI: tree, virtualised grid, detail (F4) | 5000-item category scrolls at 60fps (NF2) |
| **M4** | Playback, direct path (F7, F8, F9) + cellular guard (F13) | an MKV/HEVC file plays via direct bytes where the server allows |
| **M5** | HLS path + F12 messaging | a transcoded file plays; a 415 explains itself |
| **M6** | Search, home rows, favourite/rating/watched (F5, F6, F10) | |
| **M7** | Multi-server + secure storage (F11); background audio, lock screen, PiP (F14) after R2/R3 | |
| **M8+** | Optional: direct-play capability probe + upstream PR; offline downloads | |

---

## 11. Deferred

- Offline downloads and a download queue.
- Embedded subtitle/audio tracks libmpv can see but the API does not list.
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

### Still open

- **Q1.** Which state-management approach for the app layer? Deliberately
  deferred to M3 so it is chosen against real screens rather than in the
  abstract (§6). Not a blocker before then.
