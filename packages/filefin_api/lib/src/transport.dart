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
BaseOptions fileFinBaseOptions({
  required Uri baseUrl,
  required Duration timeout,
}) => BaseOptions(
  baseUrl: baseUrl.toString(),
  responseType: ResponseType.plain,
  connectTimeout: timeout,
  sendTimeout: timeout,
  receiveTimeout: timeout,
);
