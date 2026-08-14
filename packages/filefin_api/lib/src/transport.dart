import 'package:dio/dio.dart';

/// The `BaseOptions` every FileFin `Dio` is built from — the main client and
/// the login-only one (which must not carry the auth interceptor, §0.3), so
/// the two cannot drift apart in a way that shows up only under a session loss.
///
/// [timeout] applies to all three phases (NF5), distinguished in the error
/// rather than the configuration: "could not connect" and "answering too
/// slowly" are different problems to a user.
///
/// See D12 (`ResponseType.plain`), D13 (`followRedirects: false`), and
/// `docs/field-notes.md` for what `receiveTimeout` was measured to bound.
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
