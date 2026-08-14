# D12 — dio is configured `ResponseType.plain`, so decoding stays in `filefin_api`

**Status:** accepted (M2) · **Touches:** `transport.dart`, `json_response.dart`, `error_mapper.dart`, F1
**Retires when:** not expected to. It would take dio exposing the content-type
predicate and the decode failure separately.

## Context

dio's default is `ResponseType.json`: it inspects the content type, and decodes
the body itself when it likes what it sees.

That is two decisions, and both of them are ours:

1. **Whether the media type is acceptable.** F1's entire mechanism is a
   content-type-and-payload check. Delegating it to dio's `isJsonMimeType`
   makes the rule an implementation detail of a dependency rather than
   something `json_response.dart` states and has tests about.
2. **What a bad body means.** A malformed body under an `application/json`
   header makes dio's transformer throw, and it arrives as
   `DioExceptionType.unknown` — which `mapDioException` can only read as a
   connection failure. A truncated payload would be reported to the user as
   "could not reach the server", which is a lie they cannot act on.

## Decision

`fileFinBaseOptions` sets `responseType: ResponseType.plain`. `response.data` is
always the raw string, and both decisions above stay in this package.

## Consequences

Every response is decoded by us, so `json_response.dart` is on the path of every
call and is worth its tests. The failure modes stay distinguishable: a bad media
type and a bad body are different errors with different words.
