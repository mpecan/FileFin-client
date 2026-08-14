import 'package:dio/dio.dart';
import 'package:filefin_api/src/error_mapper.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/json_response.dart';
import 'package:filefin_api/src/probe_result.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_core/filefin_core.dart';

/// The two keys `GET /api/state` is documented to carry.
///
/// Both are required, and requiring both is the whole check. `application/json`
/// alone is answered by every JSON API in the world, and a `version` key is
/// answered by a great many of them; the conjunction is what makes the probe a
/// statement about *FileFin* rather than about JSON.
const _needsSetupKey = 'needsSetup';
const _versionKey = 'version';

/// Asks an address whether it is a FileFin server.
///
/// **A status check would be worthless**: every unmatched path answers
/// `200 text/html` from the SPA catch-all (`docs/field-notes.md`). An address
/// is accepted only when the response is `application/json` **and** the body
/// decodes to an object carrying both documented keys.
///
/// Every message names the **redacted** address — this is the add-server dialog
/// text, and a saved-server URL is typed by the user. Every outcome is
/// **returned** except two, which are questions rather than verdicts about the
/// address: `RequestCancelled` and a certificate problem ([pinner]).
Future<ProbeResult> probe({
  required Dio dio,
  required FileFinUrls urls,
  CertificatePinner? pinner,
  CancelToken? cancelToken,
}) async {
  final url = urls.state;
  final safe = redactUserInfo(url);
  try {
    final response = await dio.getUri<dynamic>(url, cancelToken: cancelToken);
    final body = jsonObject(response, requested: url);
    final missing = [
      if (!body.containsKey(_needsSetupKey)) _needsSetupKey,
      if (!body.containsKey(_versionKey)) _versionKey,
    ];
    if (missing.isNotEmpty) {
      return NotAFileFinServer(
        'the JSON at $safe is missing ${missing.join(' and ')}, so it is not '
        'a FileFin state response',
      );
    }
    final state = decodeModel(body, ServerState.fromJson, requested: url);
    return state.needsSetup
        ? FileFinServerNeedsSetup(state.version)
        : FileFinServer(state.version);
  } on NotAFileFinServerResponse catch (e) {
    return NotAFileFinServer(
      '$safe answered ${e.contentType ?? 'no content type'} rather than '
      'application/json, which is what any web page answers',
    );
  } on MalformedResponse catch (e) {
    return NotAFileFinServer('$safe sent JSON we could not read: ${e.problem}');
  } on DioException catch (e) {
    final mapped = mapDioException(e, requested: url, pinner: pinner);
    if (mapped is RequestCancelled) throw mapped;
    // Neither of these says anything about whether FileFin is here — the
    // handshake never got far enough to ask — and both are things only a
    // person can answer.
    if (mapped is CertificateNotTrusted || mapped is CertificatePinMismatch) {
      throw mapped;
    }
    // A 401, 404 or 5xx here is still "not FileFin": `GET /api/state` is
    // unauthenticated and always answers 200, so anything
    // else proves the thing at this URL is not FileFin's state route.
    // Reaching the network but getting the wrong answer is a different
    // problem from not reaching it, and the two must not be merged.
    return mapped is ConnectionFailed || mapped is RequestTimedOut
        ? ServerUnreachable(mapped)
        : NotAFileFinServer('$safe answered $mapped');
  }
}
