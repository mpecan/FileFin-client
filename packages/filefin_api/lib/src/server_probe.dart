import 'package:dio/dio.dart';
import 'package:filefin_api/src/error_mapper.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/json_response.dart';
import 'package:filefin_api/src/probe_result.dart';
import 'package:filefin_core/filefin_core.dart';

/// The two keys `GET /api/state` is documented to carry (`install.go:24`).
///
/// Both are required, and requiring both is the whole check. `application/json`
/// alone is answered by every JSON API in the world, and a `version` key is
/// answered by a great many of them; the conjunction is what makes the probe a
/// statement about *FileFin* rather than about JSON.
const _needsSetupKey = 'needsSetup';
const _versionKey = 'version';

/// Asks an address whether it is a FileFin server (F1).
///
/// **A status check would be worthless here and this is not a style
/// preference.** The server registers an SPA catch-all outside its route table
/// (`server.go:352`), so an unmatched `/api/*` path answers `200 text/html`
/// with `index.html` — verified live at v0.20.3. No path or method mismatch is
/// ever answered with a 404 or a 405. A `200` from `GET /api/state` therefore
/// proves nothing: any SPA host, any reverse proxy with a fallback, and any
/// unrelated web server answers identically.
///
/// So the probe accepts an address only when the response is
/// `Content-Type: application/json` **and** the body decodes to an object
/// carrying both documented keys. Everything else — including a `200` — is
/// "not a FileFin server", with a reason a person can read.
///
/// Every outcome is **returned**, with exactly one exception: a caller that
/// cancels its own request gets `RequestCancelled` thrown (NF5). Turning that
/// into a verdict would show "unreachable" for something the user did on
/// purpose, and would leave a caller no way to tell its own cancellation from
/// a real failure.
Future<ProbeResult> probe({
  required Dio dio,
  required FileFinUrls urls,
  CancelToken? cancelToken,
}) async {
  final url = urls.state;
  try {
    final response = await dio.getUri<dynamic>(url, cancelToken: cancelToken);
    final body = jsonObject(response, requested: url);
    final missing = [
      if (!body.containsKey(_needsSetupKey)) _needsSetupKey,
      if (!body.containsKey(_versionKey)) _versionKey,
    ];
    if (missing.isNotEmpty) {
      return NotAFileFinServer(
        'the JSON at $url is missing ${missing.join(' and ')}, so it is not '
        'a FileFin state response',
      );
    }
    final state = decodeModel(body, ServerState.fromJson, requested: url);
    return state.needsSetup
        ? FileFinServerNeedsSetup(state.version)
        : FileFinServer(state.version);
  } on NotAFileFinServerResponse catch (e) {
    return NotAFileFinServer(
      '$url answered ${e.contentType ?? 'no content type'} rather than '
      'application/json, which is what any web page answers',
    );
  } on MalformedResponse catch (e) {
    return NotAFileFinServer('$url sent JSON we could not read: ${e.problem}');
  } on DioException catch (e) {
    final mapped = mapDioException(e, requested: url);
    if (mapped is RequestCancelled) throw mapped;
    // A 401, 404 or 5xx here is still "not FileFin": `GET /api/state` is
    // unauthenticated and always answers 200 (`install.go:24`), so anything
    // else proves the thing at this URL is not FileFin's state route.
    // Reaching the network but getting the wrong answer is a different
    // problem from not reaching it, and the two must not be merged.
    return mapped is ConnectionFailed || mapped is RequestTimedOut
        ? ServerUnreachable(mapped)
        : NotAFileFinServer('$url answered $mapped');
  }
}
