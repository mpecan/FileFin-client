# D19 — pinning owns the handshake, through two hooks, over one pure policy

**Status:** accepted (M2) · **Touches:** `certificate_pinner.dart`, `pinned_adapter.dart`, `pin_decision.dart`, F15, D6
**Retires when:** dart:io hands `badCertificateCallback` the leaf certificate.
It has not, and the hook's contract says it will not.

## Context

D6 chose trust-on-first-use with pinning. Implementing it ran into three
platform facts, each of which shaped the design.

**The TLS callbacks are synchronous and `bool`-returning.** Neither
`badCertificateCallback` nor `validateCertificate` can await a secret-store read
or a user prompt.

**`badCertificateCallback` is handed the wrong certificate.** dart:io calls it
with the certificate at which chain verification *failed*, which for a
multi-certificate chain is the CA at the top, not the leaf the server presented.
Under `withTrustedRoots: false` every chain fails at the top, so a private-CA
deployment — a reverse proxy, F15's stated common case — reached the hook with
the CA.

Measured at M2 against a `[leaf, ca]` chain: the trust-on-first-use prompt named
the CA; pinning the value that prompt offered accepted **any** certificate that
CA had ever issued; and pinning the server's real certificate was refused. A
self-signed chain is one certificate long, so leaf and root are the same object
and the whole defect is invisible — which is why the fixtures now include a real
chain.

**A pooled connection skips the handshake entirely**, so anything hooked only at
connect time stops being consulted after the first request.

## Decision

**The pin is resolved into memory before the client is built.** Accepting an
unknown certificate is a separate, caller-driven act: the request fails with
`CertificateNotTrusted` carrying the observed fingerprint, the UI asks the user,
the caller writes the pin and rebuilds the client. `CertificatePinner` never
writes a pin, and a mismatch never updates one.

**We own the handshake.** `connectionFactory` calls `SecureSocket.startConnect`,
which completes the handshake and hands back a socket whose `peerCertificate`
**is** the leaf — with no request byte written yet. So the pin is compared
against the right certificate, and a refusal `destroy()`s the socket before the
request, cookie included, exists on the wire.

**Both hooks are wired**, because they answer different questions:

| hook | granularity | gives us |
|---|---|---|
| `connectionFactory` | per connection | refuse *before sending*, on every new connection |
| `validateCertificate` | per response | "still the same certificate", on every reused one |

**`badCertificateCallback` is left null**, which is dart:io's fail-closed
default. `connectionFactory` takes the handshake away from dart:io for every
direct connection, so the callback is dead code on the path that matters (§5) —
and on the one path that could still reach it, an https proxy tunnel this
package never configures, a null callback refuses rather than consulting a hook
that is handed the wrong certificate.

**Both route through `decidePin`**, one pure total function, so there is exactly
one policy and it is the one the table test proves. It takes three values and
returns one, so all twelve combinations are tested. What cannot be proven on
this machine is the wiring of the OS-trusted arm, which needs a CA-signed
certificate for `127.0.0.1`; keeping the policy pure is what confines that gap
to wiring.

## The rule order in `decidePin` is the argument

1. **No certificate means no TLS.** dio calls `validateCertificate` on every
   response including a plain-`http://` one, where the certificate is null
   (measured against dio 5.11.0). F15 permits plain http for LAN servers, so
   rejecting a null certificate would break every plain-http request the moment
   a pin was stored for some *other* server.
2. **A pin outranks OS trust, in both directions.** A pinned server whose
   certificate changes is refused even when the new one is perfectly valid; that
   is the point. A pinned self-signed certificate is accepted even though no OS
   trusts it; that is also the point. The consequence worth knowing: pinning a
   CA-signed server means its renewals need re-accepting.
3. **With no pin, OS trust decides**, and a failure is a prompt rather than an
   error — see `RejectUntrusted`.

`trustedByOs` is not guessed at either call site. `connect` learns it by setting
`onBadCertificate` to return `true`, which is **not** a relaxation: it defers the
verdict to us rather than granting one, and it is the only way to learn the
platform's opinion, because the callback fires exactly when the platform would
have refused. `validateCertificate` passes `true`, because it runs only after a
handshake that already succeeded.

`withTrustedRoots: false` whenever a pin exists, so `trustedByOs` says something
true: a pin outranks OS trust either way, and a context that still trusted the
OS roots would report `trustedByOs: true` for a certificate the pin is about to
refuse — agreement where there is none. Without a pin the default context is
used, so ordinary public HTTPS keeps working exactly as the OS says.

## Consequences

`CertificatePinner` records the last certificate seen per `host:port`, because
by the time dio surfaces the failure the synchronous callback is long gone and
the exception carries only a `HandshakeException`. Without it the error could
say "TLS failed" and nothing more, which is precisely the message F15 exists to
replace.

`pinned_adapter.dart` is the only place `dart:io` and `HttpClient` appear in the
request path, which is what keeps the rest of the package testable without a
socket.

The proxy arguments to `connect` are unused: nothing sets `HttpClient.findProxy`,
so dart:io only ever calls it for a direct connection. A proxied https
connection would tunnel through `createProxyTunnel`, which secures the socket
itself and would need its own gate; writing one now would be a branch nothing
can reach (§1, §5).
