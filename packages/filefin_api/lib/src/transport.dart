import 'package:dio/dio.dart';

/// The `BaseOptions` every FileFin `Dio` is built from.
///
/// One function so the main client and the login-only client (which must not
/// carry the auth interceptor, §0.3) cannot drift apart in a way that shows up
/// only under a session loss.
///
/// **`ResponseType.plain` is the load-bearing choice.** dio's default is
/// `ResponseType.json`, which decodes the body itself when it likes the
/// content type. That would hand two decisions to dio that belong to us:
///
/// 1. *whether* the media type is acceptable — F1's entire mechanism is a
///    content-type-and-payload check, and delegating it to dio's own
///    `isJsonMimeType` makes the rule an implementation detail of a
///    dependency rather than something `json_response.dart` states and tests;
/// 2. *what a bad body means* — a malformed body under an `application/json`
///    header makes dio's transformer throw, and it arrives as
///    `DioExceptionType.unknown`, which `mapDioException` can only read as a
///    connection failure. A truncated payload would be reported as "could not
///    reach the server", which is a lie the user cannot act on.
///
/// With `plain`, `response.data` is always the raw string and both decisions
/// stay in this package, where there are tests about them.
///
/// [timeout] is applied to all three phases (NF5): a hung server must never
/// hang the UI, and the three are distinguished in the error rather than in
/// the configuration because a user reads "could not connect" and "answering
/// too slowly" as different problems.
///
/// **`receiveTimeout` really does bound the body, not just the headers, and
/// that is measured rather than assumed.** dio's IO adapter sets it on
/// `request.close()`, which reads as time-to-headers — so M2's review predicted
/// that a server sending headers and then dripping two bytes every 100 ms would
/// hang forever. Against dio 5.11.0 with these exact options it does not: a
/// stalled body aborted after 2038 ms and a drip-fed one after 2005 ms, both
/// under a 2 s timeout, because the adapter's deadline covers the whole receive
/// rather than resetting on each chunk. `client_test.dart` pins that with a
/// real drip-feeding server: it is a fact about a dependency, and the exact pin
/// in `pubspec.yaml` is what turns a change in it into a review event.
///
/// **`followRedirects: false` is a security decision, not a default.** dio
/// follows up to five redirects, and `validateCertificate` sees only the
/// connection that served the final response — so a pinned `https` origin that
/// answered `302 -> http://impostor/api/me` had its redirect followed, the
/// pinner was asked about a **null** certificate (correct for the plain-http
/// LAN servers F15 permits, wrong for a downgraded request that began on a
/// pinned origin) and returned accept, and the client decoded an
/// unauthenticated cleartext origin's payload as the pinned server's answer.
/// Measured at M2: `status=200 body={"user":"attacker","admin":true}`. The
/// session cookie was **not** leaked — dart:io strips `cookie` across origins —
/// so this is integrity, not credential loss, and dart:io's own exemption for
/// same-scheme same-port subdomains means `https://evil.pinned.example` would
/// have kept it.
///
/// Refusing outright rather than inspecting the final URI is the M2-shaped
/// answer: no documented endpoint this client calls redirects (the wire trace
/// of all seven found none), so a redirect here is already something we do not
/// model and arrives as `ServerFailure` naming the status. M5's `307` to HLS is
/// a redirect we *do* model, and it will have to turn this on deliberately,
/// with the origin check and the "headers survive the redirect" test that
/// SPEC.md asks for — which is exactly the conversation a silent default was
/// having on our behalf.
BaseOptions fileFinBaseOptions({
  required Uri baseUrl,
  required Duration timeout,
}) => BaseOptions(
  baseUrl: baseUrl.toString(),
  responseType: ResponseType.plain,
  connectTimeout: timeout,
  sendTimeout: timeout,
  receiveTimeout: timeout,
  followRedirects: false,
  maxRedirects: 0,
);
