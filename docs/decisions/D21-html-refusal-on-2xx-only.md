# D21 — the HTML refusal applies to 2xx responses we intend to decode, and nowhere else

**Status:** accepted (M2), boundary corrected (M5) · **Touches:** `json_response.dart`, `error_mapper.dart`, F1, F3
**Retires when:** the server stops serving an SPA catch-all.

## Context

Every path this server does not route answers `200 text/html` from the SPA
catch-all (`server.go:352`). That is a *success that is not one*, and it arrives
as a JSON decode failure somewhere else entirely unless something refuses it.

The obvious generalisations are both wrong, and each is wrong in a way that
looks like tightening.

## Decision

`refuseHtml` refuses `text/html` — not "anything that is not JSON" — and it is
applied to **2xx only**, on routes we intend to decode.

## Why not "must be JSON"

The routes this guards answer `204` with no `Content-Type` at all, the poster
route answers whatever the file is, and the subtitle route answers `text/vtt`.
A client insisting on one media type would refuse responses that work. What it
refuses is the one answer that means *no route matched*.

## Why 2xx only, and why this is measured rather than reasoned

Go's `http.Redirect` writes an HTML body, so the `307` to HLS carries
`Content-Type: text/html`. Applying the refusal to redirects would refuse the
**success** case while the catch-all's `200 text/html` — the real failure —
sailed through (M5.0/E-K). The M5 plan predicted the opposite; the boundary is
tested at 206, 300 and 302.

## Why it never runs on an error response

`401 unauthorized` and `404 page not found` are served as **plain text**
(`docs/server-api.md`). A blanket content-type guard would turn every documented
error into "not a FileFin server", and **F3 would never see a 401 at all** —
which would disable the entire session-renewal path. dio throws on a non-2xx
before `_jsonBody` is reached, and `error_mapper.dart` handles those without
ever looking at a content type.

## Consequences

The check lives in `json_response.dart` with three callers across two libraries.
The third caller is what made it worth moving out of `FileFinClient`:
`SessionManager.logout` writes and reads nothing, so nothing else on its path
would ever have noticed the catch-all answering.
