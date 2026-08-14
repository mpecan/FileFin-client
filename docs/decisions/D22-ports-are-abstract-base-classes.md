# D22 — every port is an `abstract base class`, never an interface

**Status:** accepted (M2) · **Touches:** `secret_store.dart`, `library_api.dart`, `playback_host.dart`, `now_playing.dart`
**Retires when:** not expected to.

## Context

This client injects its platform edges as ports: `SecretStore`, `LibraryApi`,
`PlaybackHost`, `NowPlayingHost`. Each exists so a test can substitute a
two-line fake for a layer that otherwise needs a socket, a Keychain or libmpv —
and so `filefin_api` can stay Flutter-free, which is what keeps `dart test`
usable for it (`docs/architecture.md`).

Dart offers `abstract interface class` and `abstract base class`, and the choice
is not stylistic.

## Decision

Ports are declared `abstract base class`.

`base` forces every subtype to `extend` rather than `implement`. Two things
follow, and both are the reason:

- **A new method on the port is a compile error in every implementation**,
  rather than something an `implements` clause silently satisfies with a stub.
- **Inherited behaviour is guaranteed rather than recommended.** `SecretStore`
  is the case that matters: its redacting `toString` (§9) is *inherited* by
  every implementation. An interface could only ask implementations to redact;
  this makes an implementation that wants to print something override a method
  that already does the right thing.

## Consequences

A test fake is a two-line `extends`, which is the point. Mockito-style
`implements` mocking of these types is unavailable by construction — which has
not cost anything, because the fakes in `test/support/` are simpler than a mock
would be.
