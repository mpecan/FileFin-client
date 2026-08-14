import 'package:dio/dio.dart';

/// The `BaseOptions` every FileFin `Dio` is built from — the main client and
/// the login-only one (which must not carry the auth interceptor), so
/// the two cannot drift apart in a way that shows up only under a session loss.
///
/// [timeout] applies to all three phases, distinguished in the error
/// rather than the configuration: "could not connect" and "answering too
/// slowly" are different problems to a user.
///
/// `ResponseType.plain` keeps the media-type and decode decisions in this
/// package; `followRedirects: false` keeps a redirect from moving a pinned
/// request onto an origin the pinner never sees.
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
