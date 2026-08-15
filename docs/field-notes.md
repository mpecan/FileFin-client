# Field notes

How the server, the dependencies and the framework were **observed** to behave.
Not decisions — see [`decisions/`](decisions/) for those — and not rules. These
are facts about things we do not control, every one of them measured rather than
read from a document, and every one of them will look like a client bug the day
it bites.

**Why they are here and not in a comment.** A fact about libmpv is not a
description of any one of our functions, so there is no declaration it naturally
sits above; it usually constrains three or four files at once, and a comment can
only be found from whichever of them a reader happened to open. CLAUDE.md §2
caps a comment block at twelve lines for exactly this reason.

**Each entry names how it was measured.** A fact with no measurement behind it
is a belief, and beliefs are what this file exists to replace. When upstream
changes, the entry and its fixture change together (§8).

---

## The FileFin server

Pinned to **v0.20.3** unless an entry says otherwise. Endpoint shapes and their
upstream citations live in [`server-api.md`](server-api.md); this file holds
behaviour that the endpoint documentation does not imply.

### A non-browser-native file cannot be fetched as raw bytes

`GET .../file/{n}` answers **307** to HLS, with no override. The reverse also
holds: `.../hls/` returns **415** for a file that does *not* need transcoding.
There is no quality or bitrate parameter anywhere.

### "Browser-native" is decided by the PROBED container and codecs

But only once the probe agent has reached the row. `fileNeedsTranscode`
(`internal/server/playback.go:78`) reads `if f.Container != "" && f.VideoCodec
!= ""` and otherwise falls back to `transcode.NeedsTranscode(f.Ext)`, whose
whole vocabulary is `{.mp4, .webm, .m4v}`.

**`tool/testserver/seed.sh` never probes** — it rebuilds the cache and stops, so
`media_files.container` is `''` for every seeded row and `probe_tasks` is empty.
*Every verdict measured against the seeded library is therefore the extension
fallback.* M4's first pass read that fallback as the rule and amended SPEC §3.4;
it was wrong, and the correction cost a whole exit criterion.

Both arms are in `tool/spikes/e5_mkv_direct_play.sh`: one VP9/Opus `.mkv`,
unprobed → `transcode:true` and **307**; after `POST /api/admin/probe/scan` the
row carries `matroska,webm` / `vp9` / `opus` → `transcode:false` and **200 with
`Accept-Ranges`**. So an `.mkv` *does* direct-play. Before concluding anything
about this endpoint, look at the three format columns first.

### The 307 to HLS carries `Content-Type: text/html`

Go's `http.Redirect` writes an HTML body, so a client that refuses HTML on this
route refuses the **success** case — while the SPA catch-all's `200 text/html`,
which is the real failure, sails through. `FileFinClient._refuseHtml` is
therefore applied to **2xx only** in `requirePlayable`, and the boundary is
tested at 206, 300 and 302. Measured at M5.0/E-K; the M5 plan predicted the
opposite.

### `HEAD` on the file route works, and starts no transcode

Go 1.22's `ServeMux` matches a `GET` pattern for `HEAD` too, so a `HEAD` reaches
`handleStream`. Measured at M5.0/E-A against v0.20.3, it answers `307` for a
transcoding file, `200 video/mp4` for a direct-play one, `415` when transcoding
is off, `404` for a bad index and `401` unauthenticated.

A one-byte `GET Range: 0-0` gives identical statuses and moves a body — 81 bytes
of Go's redirect HTML on one arm, a media byte on the other — so `HEAD` is the
cheaper of two working answers rather than a guess.

**It starts no transcode**: twenty pre-flights created zero `filefin-hls-*`
session directories while one playlist request created one (M5.0/E-G). The
`307` is decided in `playbackTarget` before any ffmpeg exists. A pre-flight that
spawned one per open would be a self-inflicted denial of service on the user's
own server.

### Two different 415s exist, and a client can only ever see one

`GET .../file/{n}` answers `415 transcoding disabled` (`playback.go:115`) for a
file that needs transcoding on a server where it is off. `GET
.../file/{n}/hls/index.m3u8` answers `415 not transcodable`
(`playback.go:153`) when transcoding is off **or the file does not need it**.

This client never requests the second route — `PlaybackRequest.url` is always
the file route and libmpv follows the `307` itself — so widening
`TranscodingDisabled`'s message to cover both would describe a case that cannot
reach us.

The first is **not retryable**, measured rather than assumed: against a real
`transcodeEnabled:false` server at v0.20.3 (M5.0/E-B) the file route answered
`415` on every attempt while the detail payload kept reporting `transcode: true`
for the same file. A `HEAD` 415 also arrives with an empty body (M5.0/E-K),
which is why the variant carries no `body` field.

### Sessions are in-memory and die on restart

A `401` on any call is normal, not exceptional — re-auth and retry once (see
`filefin_api`).

### Nothing paginates

A large library returns everything in one array. Every list we draw must be
virtualised; see [D14](decisions/D14-virtualised-lists.md).

### Any path the server does not route answers `200 text/html`

The SPA catch-all (`server.go:352`, verified live at v0.20.3). A wrong path
therefore fails as a *success that is not one*, never as a 404 — which is why
`StubServer`'s default responder is the catch-all rather than a 404 the real
server never sends.

### Every write re-stamps `updated`, and every home bucket is ordered by it

The home rows come from the `user_state` mirror rather than from `meta.json`
(`media.go:227`), the mirror upsert is best-effort, and every bucket is
`ORDER BY us.updated DESC`. So **setting a rating re-orders the *Continue
watching* row** (measured M6.0/E-3). None of that is derivable from what a
client holds, which is why F6 refetches after a write rather than predicting.

### An item legitimately appears in more than one home row

The buckets are independent predicates over one `user_state` row rather than a
partition. The captured `home_populated.json` has the film in `continue` *and*
in `favorites`. Nothing de-duplicates.

`homeBucket` (`db/home.go`) applies no limit either, so a heavy user's *Watched*
row is as long as their library.

### `POST {"watched": false}` and `DELETE .../watched` are different operations

Measured against v0.20.3 at M6.0/E-5: the first returned the item to *continue*
still 45 seconds in; the second left it in no home row with the position gone.
No wording that treats un-watching as one thing can be true of both, which is
why a watched item gets a menu rather than a button.

### Category counts are `0` when the cache is unavailable

`library.go:73-81` returns `media` and `files` as 0 for a genuinely empty
category **and** for an unavailable cache. A client cannot tell them apart, so
a row that said "0 items" would state as fact something it does not know.

### `strconv.Atoi` and Dart's `int.tryParse` differ on exactly one input class

The numeric search scopes **fail closed**: `year` parses `q` with `Atoi` and
`decade` parses it after stripping one trailing `s`, and either failing returns
no rows and no error (`db/search.go:36-48`). On screen that is
indistinguishable from a library with nothing in it, so a client that wants to
say which has to mirror `Atoi`'s grammar.

Measured at M6.0/E-4, the two agree on everything the milestone plan expected
them to disagree about: Dart skips leading and trailing whitespace exactly as
`TrimSpace` does — for U+00A0 as well as for a space — both accept a leading `+`
and leading zeros, both reject `2e3`, `2_020`, `2020.0`, `٢٠٢٠` and `20 20`, and
both are 64-bit, agreeing on `9223372036854775807` and on the value above it.

They part company on one thing: **`int.tryParse` honours a `0x` prefix and
`Atoi` does not.** Proven against the live binary rather than read off the
source — `0x7E4` *is* 2020, and `field=year&q=0x7E4` came back `[]` from
v0.20.3 where `q=2020` returned the row. A bare `int.tryParse` would tell the
user a search was running that the server had already refused.

### An unrecognised search `field` degrades to `all` rather than erroring

`db/search.go:70`. A screen that dropped its scope selector still returns
plausible results and quietly ignores what the user picked — so the test that
matters asserts the wire (`search(Kurosawa, director)`), not the rendering.

### Go's `int(x + 0.5)` and Dart's `.toInt()` differ on non-finite input

Dart's `.toInt()` throws on NaN and Infinity where Go's `int()` does not. What
Go produces instead, measured on darwin/arm64 against upstream's own `round`:
`+Inf` → `9223372036854775807`, `NaN` → `0`, `-Inf` → `0` (through the negative
clamp).

So `roundReportedSeconds` returning 0 for `NaN` and `-Inf` agrees with Go by
accident of the platform, and `+Infinity` is the sole place we deliberately
answer something else. Neither is reachable over the wire — Go's
`encoding/json` refuses to marshal a non-finite float, so no server payload can
carry one. The guard is about our runtime, not about the server.

Go's `round` also differs from Dart's `.round()` for negatives: `(-0.5).round()`
is -1, and -0.5 is reachable from a seek to the very start of a file.

### The progress interval is MEDIA time, never wall clock

Upstream compares `Math.abs(el.currentTime - lastMark) >= 30`. A wall-clock
timer keeps re-reporting a paused position, and it makes F9 need a fake clock
to test.

---

## libmpv and `media_kit`

### The shipped players link mbedTLS, and iOS has no trust store behind it

Read off the built app rather than assumed. `Mbedtls.framework`,
`Mbedcrypto.framework` and `Mbedx509.framework` are all in
`Runner.app/Frameworks`, and `otool -L` on the `Mpv` binary references Apple's
**Security framework zero times** — so it never consults the iOS trust store.
`strings` finds the `tls-ca-file` option and no compiled-in default CA path.

The consequence is that on iOS, `tls-verify=yes` with no `tls-ca-file` verifies
against **no anchors at all**, and a valid public certificate fails exactly like
a self-signed one. Confirmed on an iPad Pro (iOS 26.6): playback of an
HTTPS-served file failed until the app began shipping CA roots, and worked
immediately afterwards.

**The code asserted the opposite** — "on every other platform the system libmpv
uses the OS trust store natively" — and that sentence shipped for four
milestones. `verification-backlog.md` row 20 had predicted the failure exactly.
There is no public iOS API to enumerate system roots, which is why the answer is
a shipped snapshot rather than an export.

### libmpv verifies NO certificate by default

Measured with mpv 0.41.0 against this repo's own `server_a.crt`: default → the
server logged `"GET … 200"`; `--tls-verify=yes` → `error:0A000086 certificate
verify failed` and the server logged nothing. F15's pin lives in `filefin_api`'s
socket; libmpv opens its own from native code.
[D10](decisions/D10-tls-playback-refuses.md) is the answer.

### `Media(start:)` IS honoured on an HLS VOD playlist

So F8 works over the transcode path with no fallback. Measured at M5.0/E-D
against mpv 0.41.0: `startAt: 1200 ms` produced the position stream
`[0, 1200, 1289, …]` where a `startAt: 0` control produced `[0, 89, 156, …]`.
The shipped Android and iOS builds are a different question —
[`verification-backlog.md`](verification-backlog.md) row C.

### The event order after a second `open()` is IDENTICAL on the direct and HLS paths

So `_switchTo`'s zeroing and `_positionIsCurrent` cover both. Measured at
M5.0/E-E, mid-playback, on the same host: an emptied `tracks`, then
`playing=false`, then `position=0`, then `duration=0`, then `playing=true`, then
the new file's real values. The load-bearing half of the claim
`player_controller.dart` records — `playing=false` before any position or
duration event — holds on both.

### mpv reports the PLAYLIST's duration on the HLS path, not the source file's

The seeded 3.000 s HEVC item comes back as **3.023 s**, from `#EXTINF:3.023`.
The 90% crossing is computed against whatever mpv says, so an assertion written
against the source duration is wrong by 23 ms and an exact-equality one is
simply wrong.

### libmpv surfaces no status code

A `415` arrives on `PlaybackHost.errors` as `Failed to open <url>.` and nothing
else — measured verbatim at M5.0/E-I, over a black surface. A 401 and a missing
file produce the same sentence. This is why the player pre-flights with a
`HEAD` rather than classifying a failure after the fact, and why `_recover`
asks `api.me()` to tell two indistinguishable causes apart.

### `Media`'s `httpHeaders` are cached GLOBALLY by URI

`media_native.dart`: `httpHeaders ?? cache[uri]?.httpHeaders`. A second `Media`
for the same URL with no headers inherits the first one's — so a negative
control that shares a process with its positive is **vacuous**. Measured: an
open with no cookie "succeeded" in-process and failed correctly in a fresh one.

**It is not reachable through this app's code, and saying so is the point of
keeping the entry** (M4.R/T6): the cache is consulted *only* when `httpHeaders`
is null, `MediaKitPlaybackHost.open` always passes `request.headers`, and
`PlaybackRequest.headers` is non-nullable. The separate control file and its
distinguished URI stay as defence in depth against a future caller that stops
passing them; treat this as a trap in the library, not as a live defect.

### `VideoController` constructs fine under `flutter test`; DISPOSE is what hangs

Re-measured at M4.R in a plain `test()` body with a binding up:
`VideoController(player)` returns, `Video(controller: …)` returns, and
`player.dispose()` **never** returns. The constructor body is a fire-and-forget
`() async { … }()` whose first statement awaits `addPostFrameCallback`
(`video_controller.dart:71`), so it parks a closure rather than the caller — but
it also sets `isVideoControllerAttached`, and `Player.dispose()` then awaits a
completer only that parked closure completes. **Pumping** a `Video` is the other
non-terminating case. `real_mpv_player_test.dart` covers `buildSurface` by
giving that test its own `Player` and never disposing it.

An earlier version of this entry said the constructor "does not construct… it
awaits a platform channel `flutter_tester` does not host", and
`tool/coverage-gate.sh` raised the coverage ratchet on that sentence. It was
wrong. Kept as a reminder that a measurement in prose rots silently.

### `real_mpv_player_test.dart` crashes its own runner, and it is not yours

`TestDeviceException(Shell subprocess crashed with segmentation fault.)` or
exit code `-10` (SIGBUS) takes the whole file down and every test in it reports
"did not complete", including ones that had not started.

Measured at M7.0/E-8 on this machine, mpv 0.41.0, Flutter 3.44.9: **2 crashes in
42 plain `flutter test` runs — 4.8%**; 0 in 12 `--coverage` runs;
`ps -eo pid,etime,command | grep flutter_tester` showed zero processes before
every iteration, so the orphaned-tester hypothesis is not what this is. M6.0/E-9
measured 0 in 24 standalone runs, which is entirely consistent with 4.8%
(P(0 of 24) = 0.31) — the "standalone runs never crash" reading was underpowered,
not wrong.

`tool/common.sh` carries the one retry in this repo for it: bounded at one, loud,
and narrow — it does not retry a failed assertion, and it does not retry a crash
in any other file.

---

## dio

### `receiveTimeout` really does bound the body, not just the headers

dio's IO adapter sets it on `request.close()`, which reads as time-to-headers —
so M2's review predicted that a server sending headers and then dripping two
bytes every 100 ms would hang forever. Against dio 5.11.0 with
`fileFinBaseOptions` it does not: a stalled body aborted after 2038 ms and a
drip-fed one after 2005 ms, both under a 2 s timeout, because the adapter's
deadline covers the whole receive rather than resetting on each chunk.
`client_test.dart` pins this with a real drip-feeding server. It is a fact about
a dependency, which is what the exact pin in `pubspec.yaml` is for.

### dio follows up to five redirects, and the pinner only sees the last connection

Measured at M2: a pinned `https` origin that answered `302 -> http://impostor/api/me`
had its redirect followed, the pinner was asked about a **null** certificate
(correct for the plain-http LAN servers F15 permits, wrong for a downgraded
request that began on a pinned origin) and returned accept, and the client
decoded an unauthenticated cleartext origin's payload as the pinned server's
answer: `status=200 body={"user":"attacker","admin":true}`.

The session cookie was **not** leaked — dart:io strips `cookie` across origins —
so this is integrity, not credential loss, and dart:io's own exemption for
same-scheme same-port subdomains means `https://evil.pinned.example` would have
kept it. [D13](decisions/D13-no-redirect-following.md) is the answer.

### `Headers.value` throws when a header arrived more than once

So every header this client reads is taken through the **list** form. No malice
is needed to reach it — any proxy that folds or duplicates a header does.

The two places it matters are the ones where an exception escaping the sealed
hierarchy would be worst: `Retry-After` on a `429`, where a caller doing
`on FileFinApiException` would get a raw `_Exception` exactly when login is
being rate limited; and `Content-Type` on a 2xx, which is the path a caller has
no reason to guard at all. dart:io happens to collapse a duplicated
`Content-Type` today, so that one is defence against a dependency's accident
rather than an observed payload.

### `ResponseType.json` hands two decisions to dio that are ours

It decodes the body itself when it likes the content type, which takes over
*whether* the media type is acceptable (F1's entire mechanism) and *what a bad
body means* — a malformed body under an `application/json` header makes dio's
transformer throw, and it arrives as `DioExceptionType.unknown`, which
`mapDioException` can only read as a connection failure. A truncated payload
would be reported as "could not reach the server", which is a lie the user
cannot act on. [D12](decisions/D12-plain-response-type.md).

---

## Flutter

### `DpadTraversalPolicy` weights cross-axis overlap, so a narrow control loses

It prefers candidates overlapping the source on the cross axis and then weights
cross-axis displacement. A pill 124 points wide at the left edge loses to a
full-width episode row every time — from above, because a centred *Play* does
not overlap it at all; from below, because a row centred at x=480 is 400 points
off the pill's centre and only 8 points further down.

Measured: `down` from *Play* went to S1E1 and `up` from S1E1 came back to
*Play*, with the season selector between them and reachable from neither.
Widening the pills was tried and is the fragile version of the fix — it depends
on how the policy happens to weight two axes today. A strip that spans the row
is centred by construction, so it wins on both counts.

### `FocusScope` is a traversal boundary

`inDirection` stops at its edge. `TvShell`'s rail was focusable, correct, and a
trap: focus entered the navigation and `right` never left it again. Nothing in
`analyze`, `constitution` or the widget suites saw it, because every one of them
can only ask whether a widget exists. `test/support/dpad.dart` is the answer;
CLAUDE.md records why its shape is load-bearing.

### `flutter_test`'s binding installs an `HttpOverrides` that answers 400 for everything

Measured at M3.0. A suite that wants a real socket must set
`HttpOverrides.global = null` in `setUpAll` and put it back afterwards — and its
bodies must be plain `test()`, because a real socket's callback never fires
under `FakeAsync`.

### An `Image` frame callback cannot be driven by `FakeAsync`

Reaching it needs a real image decode, which is engine-side async that a
`testWidgets` body's clock does not drive. `just mutants` proved the cost: both
`frame == null || !wasSync` and `frame != null && !wasSync` survived the whole
suite, and each of them is a tile showing a placeholder over a poster it has.
The condition is therefore a named function with its own unit test.

### Dart's `Uri` deletes dot segments unconditionally, including escaped ones

`Uri.encodeComponent` leaves `.` alone (RFC-unreserved), and `Uri` removes dot
segments even in their escaped form — writing `%2E%2E` does not help:
`Uri.parse('https://h/a/b/%2E%2E/x').path` is `/a/x`.

So percent-encoding is lossless for every *character* but not for the three
whole *segments* `''`, `'.'` and `'..'`. `ApiPaths._seg` therefore rejects those
three outright rather than encoding them, and `urls_test.dart` pins the
behaviour against a real route. `MediaId` comes straight off the wire and
defaults to `MediaId('')` (§8), so an empty segment is not hypothetical.

### `flutter test` on a package with no test files exits 0

One of the several ways a gate silently always-passes; CLAUDE.md carries the
full list.

---

## `audio_service`

### `AudioService.init` cannot be retried

`audio_service.dart:1007` opens with `assert(_cacheManager == null)`. So a
failed start must be memoised alongside a successful one — clearing the rejected
future so a second player screen could try again, which review asked for, would
turn a recoverable failure into an assertion in release mode.

### The OS mutes a backgrounded app until a media session exists

Measured at M7.6/E-6 on an Android emulator at API 37: a backgrounded player
goes from `mutedState:opControlAudio` — the AppOps `CONTROL_AUDIO` restriction —
to `mutedState:none` once the foreground service is up, and
`KEYCODE_MEDIA_PAUSE` then arrives in Dart. On iOS `UIBackgroundModes: audio` is
what stops the process being suspended, and libmpv sets
`AVAudioSessionCategoryPlayback` itself. [`risks.md`](risks.md) R3 carries both,
with their negative controls.
