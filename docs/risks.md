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

## R2 — iOS Picture-in-Picture. OPEN. *Spike before M7.*

iOS PiP is built around `AVPlayerLayer` / `AVSampleBufferDisplayLayer`. libmpv
renders into its own surface, so the OS has no layer to hand to the PiP
controller. PiP may be unavailable outright, or need custom platform work
(feeding decoded frames into an `AVSampleBufferDisplayLayer`, which is a real
project).

**Affects:** F14.
**Spike shape:** a minimal `media_kit` iOS app that attempts to enter PiP;
record whether the system offers it at all, and if not, what the cheapest
alternative costs. Result goes here and in `SPEC.md` §8.

---

## R3 — Lock-screen / MediaSession controls. OPEN. *Spike before M7.*

`media_kit` is a playback engine, not a media-session integration. Background
audio, the lock-screen transport, and the Android notification are separate
platform surfaces (`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` on iOS,
`MediaSession` on Android) that something has to drive.

**Affects:** F14, NF6.
**Spike shape:** establish what F14 actually costs on each platform — an
existing package that composes with `media_kit`, or per-platform channel code.

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
