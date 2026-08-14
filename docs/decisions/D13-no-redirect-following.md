# D13 — dio never follows a redirect

**Status:** accepted (M2), reaffirmed (M5) · **Touches:** `transport.dart`, F15, `requirePlayable`
**Retires when:** a documented endpoint starts redirecting. None of the seven
does today, and the M2 wire trace found none.

## Context

dio follows up to five redirects by default, and the certificate pinner only
ever sees the connection that served the *final* response.

Measured at M2, and the measurement is the argument: a pinned `https` origin
answered `302 -> http://impostor/api/me`. dio followed it, the pinner was asked
about a **null** certificate — correct for the plain-http LAN servers F15
permits, wrong for a downgraded request that began on a pinned origin — and
returned accept. The client then decoded an unauthenticated cleartext origin's
payload as the pinned server's answer:
`status=200 body={"user":"attacker","admin":true}`.

The session cookie was **not** leaked; dart:io strips `cookie` across origins.
So this is integrity, not credential loss — and dart:io's own exemption for
same-scheme same-port subdomains means `https://evil.pinned.example` would have
kept it. See [field notes](../field-notes.md#dio).

## Decision

`followRedirects: false`, `maxRedirects: 0`. A redirect arrives as a
`ServerFailure` naming the status.

## Alternatives rejected

**Inspect the final URI and refuse a downgrade.** More code on the security path
for a case we do not otherwise model — no endpoint we call redirects. Refusing
outright is the smaller thing to get right.

## Consequences

**The `307` to HLS is a redirect we model, and it is unaffected**, because dio
never sees it: `PlaybackRequest.url` is the file route and **libmpv** follows
the redirect itself, over its own socket, with the `Cookie` header surviving
onto the playlist and the segments (R1, retired). The only thing dio does with
that route is `requirePlayable`'s bounded `HEAD`, which wants to *read* the
`307` rather than chase it — `validateStatus: (s) => s < 400` is what makes it
return instead of throw.

An earlier draft of the comment this replaced predicted that M5 would turn
`followRedirects` on. M5 did not, and turning it on would have re-opened the
measured downgrade above in exchange for nothing at all.
`preflight_test.dart` asserts `countFor(hlsPath) == 0`, which is what pins this
off.
