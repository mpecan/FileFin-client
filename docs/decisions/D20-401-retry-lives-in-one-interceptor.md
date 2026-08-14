# D20 — the 401 retry lives in one interceptor, bounded by three separate mechanisms

**Status:** accepted (M2) · **Touches:** `auth_interceptor.dart`, `session.dart`, F3, SPEC §5.1
**Retires when:** the server stops holding sessions in memory. Upstream shows no
sign of it.

## Context

Server sessions live in memory and die with the process (L1), so a `401` on any
call is **routine rather than exceptional**. Something has to renew and replay,
and if that logic appears in more than one place the two copies will disagree
about when to stop.

## Decision

`AuthInterceptor` is the only place a `401` is interpreted. It renews the
session and replays the request once, transparently.

## The loop guards, and what each one actually guards

Three mechanisms, deliberately not one, because they fail differently:

1. **Recursion through login is structurally impossible.** `SessionManager` runs
   on a second `Dio` that does not carry this interceptor, so a 401 from
   `/api/login` never reaches the retry code. There is deliberately **no
   "is this the login path?" branch** — it would be unreachable, and §5 and
   `dead_types` exist to stop unreachable branches being written.
2. **Recursion through the retry is bounded by a marker on the request.** One
   retry, always, whatever else happens.
3. **Concurrency is handled by `SessionManager`**, which is where the state is.
   The interceptor's only job there is to stamp the generation each request was
   issued under, so a 401 arriving after someone else has already renewed can be
   recognised as stale.

A single guard would have to cover all three, and the one that gets written in
practice is a path check — which is the one that is both unreachable and
unbounded.

## Consequences

`apps/mobile` never sees a routine 401 and has no retry logic of its own. A
`SessionExpired` reaching the app therefore means something the retry could not
fix: no stored session, or no password to renew with (`session.dart:137`,
`:223`) — which is what its wording has to say.
