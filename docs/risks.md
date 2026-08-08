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
