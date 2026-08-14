import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';

/// The media type this server writes for every JSON route.
///
/// `writeJSON` (`server/server.go:463`) sets exactly `application/json`, and
/// `X-Content-Type-Options: nosniff` is set on every response
/// (`server.go:367-377`) — so the server always declares a type and means it,
/// which is what makes checking it worth anything. Anything else on a route we
/// expect JSON from is a transport failure, not a payload.
const _jsonMediaType = 'application/json';

/// Refuses an HTML body on a **2xx** from a route that does not serve HTML.
///
/// `text/html` specifically rather than "must be JSON", and **2xx only** — a
/// boundary that is measured rather than reasoned, because the `307` to HLS
/// carries `text/html` too. D21 has both arguments and what each one costs if
/// generalised.
void refuseHtml(Headers headers, Uri requested) {
  final contentType = headers[Headers.contentTypeHeader]?.firstOrNull;
  if (contentType != null &&
      contentType.split(';').first.trim().toLowerCase() == 'text/html') {
    throw NotAFileFinServerResponse(requested, contentType);
  }
}

/// Reads a **2xx** response as a JSON object.
///
/// Throws `NotAFileFinServerResponse` when the media type is not JSON, and
/// `MalformedResponse` when the body is not a JSON object.
Map<String, Object?> jsonObject(
  Response<dynamic> response, {
  required Uri requested,
}) {
  final decoded = _jsonBody(response, requested: requested);
  if (decoded is! Map<String, Object?>) {
    throw MalformedResponse(
      requested,
      'expected a JSON object, got ${decoded.runtimeType}',
    );
  }
  return decoded;
}

/// Reads a **2xx** response as a JSON array of objects.
///
/// Every listing endpoint answers an array and none of them paginates
/// (SPEC.md L2), so this is the shape half the client's calls return. A
/// non-object element fails the whole response rather than being skipped:
/// silently dropping a row is the failure G5 forbids, and the blast radius is
/// recorded in STATE.md rather than hidden.
List<Map<String, Object?>> jsonObjects(
  Response<dynamic> response, {
  required Uri requested,
}) {
  final decoded = _jsonBody(response, requested: requested);
  if (decoded is! List<Object?>) {
    throw MalformedResponse(
      requested,
      'expected a JSON array, got ${decoded.runtimeType}',
    );
  }
  return [
    for (final element in decoded)
      if (element is Map<String, Object?>)
        element
      else
        throw MalformedResponse(
          requested,
          'expected every array element to be an object, got '
          '${element.runtimeType}',
        ),
  ];
}

/// Runs [fromJson] over server data, turning any decode failure into ours.
///
/// The values come from a server we do not control (§8), so a mismatched type
/// is a fact about the payload rather than a bug in the caller.
///
/// **`TypeError` and nothing else**, deliberately: it is what a wrong wire type
/// produces (measured M1.10 — 124 of 208 fixture mutations do exactly that),
/// and catching `Object` would swallow a real bug in one of our own converters
/// and report it as the server's fault. There is no `FormatException` arm
/// because no model here parses a date or number from a string (§1).
T decodeModel<T>(
  Map<String, Object?> json,
  T Function(Map<String, Object?>) fromJson, {
  required Uri requested,
}) {
  try {
    return fromJson(json);
    // `avoid_catching_errors` is right almost everywhere and wrong exactly
    // here: this IS the wire boundary, and a `_TypeError` raised by a
    // generated decoder is a fact about the server's payload rather than a
    // programming error of ours. Letting it escape would put a raw Dart
    // `TypeError` in front of a user whose server simply changed a field.
    // ignore: avoid_catching_errors
  } on TypeError catch (e) {
    throw MalformedResponse(requested, '$e');
  }
}

/// Checks the media type, then decodes the raw body.
///
/// **The check is applied here and nowhere else, which is the point** — D21.
/// dio throws on a non-2xx before this is reached, and `error_mapper.dart`
/// handles those without ever looking at a content type.
///
/// The content type is read through the **list** form, because dio's
/// `Headers.value` throws on a repeated header (`docs/field-notes.md`) and an
/// exception here would escape the sealed hierarchy on a 2xx.
Object? _jsonBody(Response<dynamic> response, {required Uri requested}) {
  final contentType = response.headers[Headers.contentTypeHeader]?.firstOrNull;
  if (!_isJson(contentType)) {
    throw NotAFileFinServerResponse(requested, contentType);
  }
  try {
    return jsonDecode('${response.data ?? ''}');
  } on FormatException catch (e) {
    throw MalformedResponse(requested, e.message);
  }
}

/// True when [contentType] is `application/json`, parameters and case aside.
///
/// The parameter is dropped rather than matched: `application/json` and
/// `application/json; charset=utf-8` are the same media type, and a client
/// that rejected the second would break the first time a proxy added one.
bool _isJson(String? contentType) =>
    contentType != null &&
    contentType.split(';').first.trim().toLowerCase() == _jsonMediaType;
