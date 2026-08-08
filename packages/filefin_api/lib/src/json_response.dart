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

/// Runs [fromJson] over server data, turning any decode failure into ours.
///
/// The values come from a server we do not control (§8), so a type that does
/// not match is a fact about the payload, not a bug in the caller — and the
/// caller must be able to catch it in the same vocabulary as everything else.
///
/// `TypeError` is caught and nothing else, deliberately. It is what a wrong
/// wire type produces: `filefin_core`'s generated decoders throw `_TypeError`
/// on a `bool` where an `int` belongs (measured at M1.10 — 124 of 208 fixture
/// mutations do exactly that). Catching `Object` here would also swallow a
/// real bug in one of our own converters and report it as the server's fault,
/// which is the more expensive mistake. No model this client decodes parses a
/// date or a number from a string, so there is no `FormatException` arm; add
/// one with the first model that needs it rather than ahead of it (§1).
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
/// **The check is applied here and nowhere else, which is the point.** It
/// belongs to a 2xx response we intend to decode. Applied to every response it
/// would be catastrophic in a way that looks like tightening: `401
/// unauthorized` and `404 page not found` are served as plain text
/// (`docs/server-api.md`), so a blanket guard would turn every documented
/// error into "not a FileFin server" and F3 would never see a 401. dio throws
/// on a non-2xx before this function is ever reached, and `error_mapper.dart`
/// — which never looks at a content type — is what handles those.
Object? _jsonBody(Response<dynamic> response, {required Uri requested}) {
  final contentType = response.headers.value(Headers.contentTypeHeader);
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
