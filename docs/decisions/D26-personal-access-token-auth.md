# D26 — a token authenticates through a port, not through `SessionManager`

**Status:** accepted (M9) · **Touches:** `filefin_api`'s `AuthSession`,
`SessionManager`, `TokenAuthSession`, `AuthInterceptor`,
`TokenAuthInterceptor`, `FileFinClient`; `apps/mobile`'s `SavedServer.authMode`,
`sign_in_page.dart`
**Retires when:** the server grows a second bearer-auth mechanism this client
also needs to support, at which point `AuthSession` gains a third
implementation rather than being redesigned.

## Context

FileFin 0.21.0 accepts `Authorization: Bearer <token>` on every authenticated
route, alongside the session cookie. A token is minted from the server's own
Settings page, carries the full permissions of the owning account, has no
expiry, and is individually revocable; blocking the account cuts it off too.

The client's only auth path today is username+password: `POST /api/login`
sets a session cookie, `AuthInterceptor` silently renews it on a `401` by
replaying the stored password, and `SessionManager` owns all of that state.
None of it applies to a token — there is nothing to renew a token *with*. A
`401` on a bearer-authenticated request means the token is wrong or was
revoked, full stop, and the honest answer is to ask for a new one.

## Decision

A small port, `AuthSession`, names the three things `FileFinClient` actually
needs from a signed-in server regardless of credential kind: `forget()`,
`headers()` (what a raw caller — libmpv — must send), and `resume()`
(cold-start recovery, however this credential kind supports it). It is
`abstract base class`, the same shape as `SecretStore`, so the redacting
`toString()` is inherited rather than merely recommended.

`SessionManager` becomes the password implementation behind that port with
**no behavioural change** — every existing test kept passing untouched, which
is the proof the extraction was mechanical. `TokenAuthSession` is the new
one: `verify()` proves a token against `GET /api/me` and stores it only once
proven; `restore()` does the same from the secure store on a cold start and
**deletes** the token on a `401` rather than keeping it — unlike a lost
session cookie, there is no separate credential underneath a token that might
still be good, so keeping a known-dead one serves nothing.

`TokenAuthInterceptor` is a new interceptor, not a branch inside
`AuthInterceptor`: it attaches the bearer header on every request and maps a
`401` straight to `InvalidToken`, with no generation counter, no in-flight
future, and no replay — none of `SessionManager`'s concurrency guards apply,
because there is nothing to retry. `FileFinClient.forServer` (password) and
the new `FileFinClient.forTokenServer` (token) each wire the matching pair —
`CookieManager` + `AuthInterceptor` + `SessionManager`, or just
`TokenAuthInterceptor` + `TokenAuthSession` — so neither mode's wiring knows
the other exists.

`InvalidToken` is a new sealed variant of `FileFinApiException` rather than a
reuse of `InvalidCredentials`: the latter's message says "rejected that
username and password", which would be a lie for a token, and — unlike
`InvalidCredentials`, which can only ever fire from an active login attempt —
`InvalidToken` can also fire mid-session, from an ordinary request, once a
token is revoked. `describeApiError` sets `needsSignIn: true` for it
unconditionally for that reason.

`SavedServer` gains `authMode` (`password` | `token`), persisted in
`settings.json` like `lastUser` — it is not a secret, it says which kind of
credential to ask for. `sign_in_page.dart` gets a `SegmentedButton` toggle
that swaps the username+password fields for a single token field; the trust-
and-pin loop around it is unchanged, since a certificate can be untrusted
regardless of which credential is behind it.

## Alternatives rejected

**Send the token through `POST /api/login`, as a password substitute.** The
server does not authenticate a token that way at all — `auth.go`'s
`authUserFromBearer` reads the `Authorization` header directly on every
request; there is no server-side "log in with a token" endpoint to call.
Login and bearer auth are two different mechanisms, not two payloads for one
route.

**No interceptor — attach the header at each call site.** `filefin_api` has
roughly fifteen call sites across `client_browse.dart`, `client_playback.dart`
and `client_watch_state.dart`. That duplicates exactly the concern
`AuthInterceptor` exists to centralise once, and two copies is two chances to
get the header name wrong on one of them.

**Reuse `InvalidCredentials` for a rejected token.** Its message names
"username and password", which a token-mode user never typed, and its
`needsSignIn` story assumes it can only fire during a login attempt — false
for a token, which can be revoked mid-session. A second, honestly-worded
variant costs one class and keeps every message true.

**A token-management UI in this client** (`POST/GET/DELETE
/api/profile/tokens`). Out of scope for this milestone (§1): the client
authenticates with a token a user already has, minted from the server's own
Settings page. Creating and revoking tokens in-app is a separate, purely
additive follow-up.
