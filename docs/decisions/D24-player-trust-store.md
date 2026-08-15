# D24 — the player verifies against the device's store where it can, and shipped roots where it cannot

**Status:** accepted (M8.R) · **Touches:** `ca_bundle.dart`, `media_kit_playback_host.dart`, F15, D10
**Retires when:** iOS exposes a public API for enumerating system trust
anchors, or `media_kit` ships an iOS libmpv built against Apple's Security
framework. Either makes the shipped snapshot unnecessary.

## Context

The players we ship link **mbedTLS on both platforms** — `Mbedtls.framework` is
in the iOS app bundle, and the `Mpv` binary references Apple's Security
framework **zero times**. mbedTLS has no system trust store. With no
`tls-ca-file`, `tls-verify=yes` verifies against no anchors at all, so a
perfectly ordinary Let's Encrypt certificate is refused exactly like a
self-signed one.

Android was fixed by exporting the device's live store through a platform
channel. **iOS was assumed not to need it** — the code said "on every other
platform the system libmpv uses the OS trust store natively" — and that
assumption was never measured. It was wrong, and
`docs/verification-backlog.md` row 20 had predicted precisely this failure.

The obvious fix does not port: **iOS has no public API to enumerate system root
certificates.** `SecTrustCopyAnchorCertificates` is macOS-only. There is
nothing to export.

## Decision

`CaBundle` resolves a PEM file in preference order:

1. **The device's own store**, exported by the host through the platform
   channel. Android answers this; nothing else does.
2. **Roots shipped in the app** — Mozilla's set as distributed by curl,
   MPL-2.0, a Compatible Licence in the EUPL's Appendix — written to an
   injected cache directory.

The device's store wins whenever it exists, because it is current and it holds
the enterprise and user-installed roots a shipped file cannot.

The shipped copy is **rewritten on every cold start**, never written once. An
app update ships a new bundle, and a cached copy from the previous version would
keep a revoked root alive and hide a newly added one for as long as the install
lasts.

## Consequences

**The player's trust now diverges from the API client's, and only on iOS.**
`dio` goes through `dart:io`, which uses Apple's trust store and therefore
honours enterprise and user-installed CAs. The player uses the shipped snapshot,
which cannot. So on iOS:

- a **private or enterprise CA** the device trusts will authenticate the API
  calls and then be **refused by the player**;
- the user-visible symptom is a library that browses perfectly and refuses to
  play, which reads as a playback bug rather than a trust one.

That case is not covered and is recorded as such rather than papered over. The
per-server allowance (D10) is what a user reaches for meanwhile, at the cost
that banner names.

**The snapshot goes stale.** It is a file in the repository, refreshed
deliberately: `curl -O https://curl.se/ca/cacert.pem`, digest checked against
`https://curl.se/ca/cacert.pem.sha256`. A root added after the last refresh is
not trusted by the player until someone updates it.

**A trust store we cannot write is not a launch failure.** The write is guarded;
on failure `tls-ca-file` is left unset and playback refuses on its own terms.

## Alternatives rejected

**Treat iOS `osTrustedTls` as unverifiable and route it through D10's
allowance.** Honest, and adds no trust surface — but the banner would then
appear for servers that are genuinely fine, which teaches people to dismiss the
one warning that matters.

**Verify through a custom mbedTLS callback into Apple's APIs.** Not reachable:
mpv exposes no hook for it, and reaching one would mean patching the prebuilt
library we deliberately do not compile.
