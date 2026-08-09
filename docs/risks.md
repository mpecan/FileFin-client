# Risks

Each risk gets a spike **before** the milestone that depends on it. Nothing
here is assumed resolved; a risk moves to RETIRED only with a harness anyone
can re-run and a negative control that was seen to fail.

---

## R1 — Do HTTP headers survive the 307 to HLS? ✅ RETIRED 2026-08-08

**Why it mattered.** SPEC.md §5.3's entire streaming design is one line:

```dart
Media(streamUrl, httpHeaders: {'Cookie': 'filefin_session=$token'})
```

Every authenticated route needs that cookie, including the HLS segments
(`server/server.go:283`). If libmpv had dropped the header when following the
`307` from `/file/{n}` to `/hls/index.m3u8`, or when fetching segments named by
the playlist, the transcode path would have needed a local proxy — a whole
layer the native stack was chosen to avoid. It affected M5 and, through it, G2.

**How it was retired.** libmpv embeds FFmpeg's `libavformat` for HTTP and HLS,
so `ffmpeg` exercises the same code path — no player build required. Against a
real seeded server (`tool/testserver/seed.sh`), on the HEVC item that 307s:

| Run | Result |
|---|---|
| `ffmpeg -headers 'Cookie: filefin_session=…' -i …/file/0` | followed the `307`, fetched the playlist **and the segments**, decoded — **exit 0** |
| **negative control**, identical command with no cookie | **exit 8**, `401 Unauthorized` |
| byte-level | `index.m3u8` → `200`; `seg0.ts` → `200 video/mp2t` |

The negative control is what makes this a result rather than an anecdote: the
test could fail, and did, for the stated reason.

**Conclusion.** One `httpHeaders` map covers both playback paths. §5.3 holds
and M5 needs no alternative design.

**Harness:** `tool/spikes/r1_headers_across_redirect.sh` — re-runnable.

This risk is **retired**, not "provisionally retired" and not "to be confirmed
at M4". Do not downgrade it without a run that contradicts the above.

---

## R5 — TLS: the binary has no listener, and one arm stays unexercised

Not a risk to a milestone so much as two facts that would otherwise be
rediscovered, both measured at M2 against v0.20.3 and dio 5.11.0.

### The `filefin` binary serves no TLS at all

No `ListenAndServeTLS`, no certificate flag, nothing TLS-shaped anywhere in
`internal/` or `cmd/`. TLS is a reverse-proxy concern upstream.

So SPEC.md §10's M2 exit criterion — "a self-signed server connects only after
explicit accept, and a changed fingerprint blocks" — **cannot be met against
`filefin`**. It is met against a Dart `HttpServer.bindSecure` serving one of two
committed self-signed certificates (`packages/filefin_api/test/support/certs/`):
a real handshake with a real `X509Certificate`, just not a real FileFin. Recorded
so nobody later reads it as an omission, and so nobody goes looking for a TLS
flag that does not exist.

### `badCertificateCallback` alone would have been a hole, and the fix is measured

SPEC.md §6's original TLS row named `badCertificateCallback` and a pinned
fingerprint store. That is not sufficient, because **dart:io calls it only for a
chain the `SecurityContext` does not trust**: a server pinned while self-signed
that later gets a Let's Encrypt certificate changes fingerprint with the
callback never firing — exactly the silent re-accept F15 forbids.

The obvious repair — dio's `validateCertificate` — turns out to reject **after
the request has been sent**. Measured with a spike against a real TLS server:

| Hook | When it runs | Server saw |
|---|---|---|
| `badCertificateCallback` → false | during the handshake | **nothing** (`[]`) |
| `validateCertificate` → false | after response headers arrive | **the request** (`[/w]`) |

A design resting on `validateCertificate` alone would therefore hand the
request — session cookie included — to a server whose certificate had changed,
and only then object.

**What was built first, and why it was wrong.** Whenever a pin existed the
client was built on `SecurityContext(withTrustedRoots: false)`, so every
certificate reached `badCertificateCallback` and the decision happened before
any bytes were sent. The reasoning above is sound and the conclusion was still
wrong, because of a fact about that hook the spike never had to confront:
**`badCertificateCallback` is handed the certificate at which chain
verification failed, which for a multi-certificate chain is the CA at the top,
not the leaf.** With no trusted roots every chain fails at the top, so the pin
was compared against the CA.

The committed test certificates were **self-signed**, where the chain is one
certificate long and leaf == root — so the whole suite passed against a
mechanism that was wrong for every real deployment. A private CA in front of a
self-hosted server is F15's *stated common case*. Measured at M2.9 against a
real `[leaf, CA]` chain:

- the trust-on-first-use prompt showed the **CA's** subject and fingerprint, so
  a user comparing against their own server's certificate would see a mismatch
  and a user who accepted stored a **CA pin** — which admits any certificate
  that CA has ever issued;
- with that pin in place, an impostor holding another certificate from the same
  CA completed the handshake and **received 106 bytes of request, session cookie
  included**, before `validateCertificate` objected — the exact failure the
  table above exists to prevent;
- pinning the server's **real** certificate, as `openssl x509 -fingerprint
  -sha256` prints it, was refused.

**What is built now:** `HttpClient.connectionFactory`. `CertificatePinner.connect`
runs the handshake itself with `SecureSocket.startConnect`, compares
`socket.peerCertificate` — which *is* the leaf — against the pin, and
`destroy()`s the socket on a mismatch before dart:io writes a request byte. Its
`onBadCertificate` returns true not to relax anything but to learn the OS's
verdict, which is `decidePin`'s third input. `validateCertificate` stays wired
to the same pure `decidePin` as the per-**response** backstop, because a pooled
connection never handshakes again. `badCertificateCallback` is left null, which
is dart:io's fail-closed default.

The fixtures are the durable half of the fix: `test/support/certs/ca`,
`server_c` (a leaf it signed) and `server_d` (a second leaf, standing in for an
impostor). A self-signed-only fixture set cannot fail this test, which is
precisely why it did not.

### The gap that remains

**The OS-trusted arm is enforced but unexercised.** Proving the wiring needs a
CA-signed certificate for `127.0.0.1`, which does not exist. `decidePin` is pure
and table-tested over all its combinations, which confines the untested part to
wiring rather than policy — but it is untested, and this is where that is said.

**Consequence for the user, worth stating:** pinning a CA-signed server means
every certificate renewal changes the fingerprint and needs re-accepting. That
is F15's bargain rather than a defect, and the error names both fingerprints.

**Also outstanding, as an M3 prerequisite:** F15 permits plain `http://` for LAN
servers, and neither platform allows it by default. Android needs
`cleartextTrafficPermitted` in a network security config; iOS needs
`NSAllowsLocalNetworking` in `Info.plist`. Neither file exists yet — there is no
`apps/mobile` — and without them every plain-http server will fail on device for
a reason that looks nothing like its cause.

---

## R2 — iOS Picture-in-Picture. ❌ DECLINED at M7.6, not retired.

**Spiked at M7.6/E-7**, as a static read of `media_kit_video` 2.0.1's iOS
sources rather than a run, because the answer is decided by what is `private`
and a run cannot make a sealed symbol reachable.
**Harness:** `tool/spikes/e7_ios_pip_reachability.sh` — it asserts each fact in
its own direction and exits 1 when any of them changes, so an upstream bump
re-opens this rather than inheriting the verdict. Proven able to fail by making
`VideoOutput.texture` public in a copy of the package: `CHANGED
VideoOutput.texture: expected SEALED, found REACHABLE`, exit 1.

| Link | Verdict |
|---|---|
| `TextureGLESContext.pixelBuffer` (`gles/TextureGLESContext.swift:5`) | `public let CVPixelBuffer` — **reachable** |
| `TextureHW.copyPixelBuffer()` (`TextureHW.swift:42`) | `public` — **reachable** |
| pixel format (`gles/OpenGLESHelpers.swift:39`) | `kCVPixelFormatType_32BGRA`, which is what `AVSampleBufferDisplayLayer` takes |
| `VideoOutput.texture` (`common/VideoOutput.swift:34`) | `private` — **sealed** |
| `VideoOutputManager.videoOutputs` (`common/VideoOutputManager.swift:8`) | `private` — **sealed** |
| `MediaKitVideoPlugin.videoOutputManager` (`common/MediaKitVideoPlugin.swift:35`) | `private`, and its `init` is internal — **sealed** |
| any PiP vocabulary in the package | none, Dart or Swift — **sealed** |

So the frame is exactly the right *type* and no instance of it is reachable.
The only public entry point into the plugin is `MediaKitVideoPlugin.register(with:)`,
which returns nothing.

**Two second-order costs, recorded so nobody prices this as "just a fork".**
The buffers come from a three-deep `SwappableObjectManager` pool that Flutter's
own `copyPixelBuffer()` recycles, so a display layer holding one competes with
the texture that draws the video; and the frames carry no presentation
timestamps, which `AVSampleBufferDisplayLayer` requires — a `CMSampleBuffer`
timing layer would be ours to invent.

**Decision.** PiP is **not in F14's wording** (`SPEC.md:298` — "background audio
and lock-screen transport controls"); it appeared only in SPEC §10's M7 row.
That row is amended to match F14, and R2 is recorded as declined with the
measurement that declined it. **What would reopen it:** `media_kit_video`
exposing the texture or shipping PiP itself — which is what the harness watches
for.

---

## R3 — Lock-screen / MediaSession controls. ⚠️ PARTLY RETIRED at M7.6.

**Spiked at M7.6/E-6** against a scratch app (never `apps/mobile`, §1) on a real
Android emulator (API 37) and the iOS simulator (iOS 26.5), five arms, each
build separate because two of the three variables are build-time.
**Harness:** `tool/spikes/e6_background_playback.sh <arm>`. The instrument is
one line a second from Dart — `TICK wall=… pos=… playing=… life=…` — so `pos`
advancing while `life=paused` is decoding in the background, measured rather
than inferred.

### The first finding is a client default, not an OS behaviour

`media_kit_video`'s `Video` widget takes `pauseUponEnteringBackgroundMode` and
it **defaults to `true`**: on `AppLifecycleState.paused` it calls
`player.pause()` itself (`video_texture.dart:281-299`). With the default left
alone every arm reads "playback stops when backgrounded" and the cause is a
widget argument. That is arm `android-bare-pausebg`, and it is the negative
control for the whole spike: `pos` froze at 18941 ms and stayed there for the
full 60 s while the wall clock ran to 80 s.

`resumeUponEnteringForegroundMode` defaults to `false`, so the same widget
would also have left playback paused on return — which is NF6's second half.
`apps/mobile` passed neither argument until M7.6.

### Android — audio survives, but the OS mutes it without a session

All measurements on one emulator, API 37, `dumpsys audio`'s `mutedState` field.

| Arm | `pos` over a 60 s background | OS audio state, backgrounded |
|---|---|---|
| `android-bare-pausebg` (the default) | **frozen** at 18941 ms | `state:stopped` |
| `android-bare` (`pauseUponEnteringBackgroundMode: false`) | **advanced 1:1 with the wall clock**, 19 s → 80 s | `state:started mutedState:opControlAudio` |
| `android-service` (`audio_service`: MediaSession + foreground service) | advanced 1:1 | `state:started mutedState:none` |

Read in the same run, both directions: foregrounded, the bare arm reports
`mutedState:none`; backgrounded, `mutedState:opControlAudio`. So **decoding
continues with no package at all, and the AppOps `CONTROL_AUDIO` restriction is
what silences it** — which is precisely what a foreground service plus a
`MediaSession` lifts.

With `audio_service` running, `dumpsys media_session` showed a live session
carrying our metadata (`description=E-6 spike clip, FileFin`), a
`FOREGROUND_SERVICE|ONGOING_EVENT` notification with `category=transport`, and
a registered `MediaButtonReceiver`. `adb shell input keyevent
KEYCODE_MEDIA_PAUSE` produced `E6 REMOTE pause` **in Dart** and froze `pos` at
91039 — a transport command reaching the player, measured end to end.

### iOS — the process is suspended without the plist key, and the simulator cannot answer the audio half

| Arm | Result |
|---|---|
| `ios-bare` (no `UIBackgroundModes`) | last `TICK` at `wall=20007`, immediately after `LIFECYCLE paused`. **The process is suspended**; the Dart timer stops with it |
| `ios-plist` (`UIBackgroundModes: audio`, nothing else) | `TICK`s continue for the whole 60 s and `pos` advances 1:1, `life=paused` throughout |

An `audio_session`-configured arm behaved identically to `ios-plist`, so the
package added nothing — and the reason is in the shipped binary rather than in
the app. `nm -u` on `media_kit_libs_ios_video` 1.1.4's **device** slice shows
libmpv itself importing `_OBJC_CLASS_$_AVAudioSession`,
`_AVAudioSessionCategoryPlayback`, `_AVAudioSessionModeMoviePlayback` and
`setCategory:error:`. mpv's own `ao_audiounit` sets the category, so nothing on
our side has to.

**What the simulator cannot say, and it is a property of the binary rather than
a hedge.** The same package ships libmpv twice with different audio outputs:

```
ios-arm64                   -Daudiounit=enabled
ios-arm64_x86_64-simulator  -Daudiounit=disabled -Dcoreaudio=disabled -Dopensles=disabled
```

There is **no audio output compiled into the simulator build at all**, so
playback there runs off the video clock and "the sound kept coming" is not a
claim the simulator arms can make. The device arm was attempted and blocked:
`devicectl` installed the spike onto a real iPhone (iOS 26.6) and the launch was
refused — `FBSOpenApplicationErrorDomain error 7 … the device was not, or could
not be, unlocked`. That half is `docs/verification-backlog.md` row L.

### What it cost, and what R3 still owes

F14's Android half needs `audio_service`; its iOS half needs one `Info.plist`
key. **Not retired**, because two claims remain device-only and are rows L and M:
whether audio is audible on the shipped iOS build, and whether the Android
foreground service survives Doze over a long background.

**Affects:** F14, NF6.

---

## R4 — F-Droid and prebuilt binaries. ADVISORY, not blocking.

**The licensing position, recorded in M0 as required** (SPEC.md §8 R4, "we
never looked is not an answer worth carrying"):

- `media_kit` ships **prebuilt** libmpv binaries via `media_kit_libs_*`.
- mpv is LGPL-2.1-or-later by default, and can be built GPL depending on which
  optional components are enabled. The prebuilt libraries are the reason we do
  not compile it ourselves and therefore do not choose that flag.
- SPEC.md C6 sets distribution to **direct APK** and TestFlight/sideload. No
  app store submission means no store review gate — which defuses the App Store
  question that has historically been the hard blocker for mpv-based iOS apps.
- It does **not** defuse F-Droid. Their inclusion policy requires building
  everything from source in their own buildserver, and a prebuilt `libmpv.so`
  fails that on its face. Building libmpv from source inside their pipeline is
  substantial work.

**Consequence:** F-Droid is explicitly *not* a commitment (SPEC.md C6, D8).
Direct APK is the Android release path and has no such constraint. Downgraded
from blocking to advisory — spike it only if F-Droid becomes a real
requirement, and expect the answer to be "build libmpv from source or do not
ship there".

**What would reopen this:** a decision to submit to any app store, or to
F-Droid. Both change the question from "which licence" to "who compiles it".

---

## Retired risk log

| Risk | Retired | Evidence |
|---|---|---|
| R1 — headers across the 307 | 2026-08-08 | `tool/spikes/r1_headers_across_redirect.sh`, with a negative control that failed as required |

R5 is not in that table on purpose. It is not retired: one arm of it is
enforced without being exercised, and saying so is worth more than a tick.

## R6 — libmpv verifies no certificate, so F15 does not reach playback

**Measured at M4.0, both directions, against this repository's own committed
self-signed certificate** (`packages/filefin_api/test/support/certs/server_a.crt`,
served by a Python `ssl` server on `127.0.0.1:8443`), with mpv 0.41.0:

```
$ mpv --vo=null --ao=null --no-config --frames=1 https://127.0.0.1:8443/movie.mp4
rc=0        server log: 127.0.0.1 - - [...] "GET /movie.mp4 HTTP/1.1" 200

$ mpv --vo=null --ao=null --no-config --frames=1 --tls-verify=yes \
      https://127.0.0.1:8443/movie.mp4
rc=2        [ffmpeg] tls: error:0A000086:SSL routines::certificate verify failed
            server log: unchanged — the request never arrived
```

Through `media_kit`, in the same shape:
`setProperty('tls-verify', 'yes')` then opening that URL is **refused**;
with `'no'` the same open **plays** (`duration=0:00:03`).

So the property is settable, load-bearing and **off by default**. F15 pins the
certificate on `filefin_api`'s socket; libmpv opens its own from native code and
has no pin to consult.

**What was done about it: D10** (SPEC §13). `decide()` takes a
`PlaybackTransport` and refuses `pinnedTls` unless a **per-server** override says
otherwise, and the override carries a persistent banner rather than a
dismissible dialog, because what is given up is ongoing. `plainHttp` plays (F1
already warns in words); `osTrustedTls` plays with `tls-verify=yes`.

**Not retired.** Two things are unverified and both have backlog rows: whether
the *shipped* Android and iOS libmpv builds behave the same way (row 20), and
whether the cookie reaches them at all (row 18). Every measurement above used
Homebrew's build.
