part of 'errors.dart';

/// A `415`: this file needs transcoding and the server has it turned off.
///
/// **F12's variant, and the wording is the whole reason it exists.** SPEC.md
/// F12 asks that a 415 be explained as "transcoding is disabled on the server
/// and this file needs it", never as "playback failed" — so this cannot be
/// `ServerFailure`, whose message is "the server answered 415" and is exactly
/// the sentence F12 forbids.
///
/// **It is not retryable, and that is measured rather than assumed.** Against a
/// real `transcodeEnabled:false` server at v0.20.3 (M5.0/E-B), the file route
/// answered `415 transcoding disabled` on every attempt while the detail
/// payload kept reporting `transcode: true` for the same file. The setting is
/// the server's; nothing a client does changes the answer.
///
/// **Two different 415s exist upstream and a client can only ever see one of
/// them.** `GET .../file/{n}` answers `415 transcoding disabled`
/// (`playback.go:115`) for a file that needs transcoding on a server where it
/// is off — that is this variant. `GET .../file/{n}/hls/index.m3u8` answers
/// `415 not transcodable` (`playback.go:153`) when transcoding is off **or the
/// file does not need it**; this client never requests that route, because
/// `PlaybackRequest.url` is always the file route and libmpv follows the `307`
/// itself. Widening the message to cover both would describe a case that cannot
/// reach here.
///
/// There is deliberately **no `body` field**. Only one shape is reachable, and
/// the pre-flight that produces this is a `HEAD` — measured at M5.0/E-K, a
/// `HEAD` 415 arrives with an empty body, so a `body` would be a field that is
/// always blank at exactly the moment it is constructed.
final class TranscodingDisabled extends FileFinApiException {
  /// [requested] needs transcoding and this server will not do it.
  const TranscodingDisabled(this.requested);

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'TranscodingDisabled: ${redactUserInfo(requested)} needs transcoding '
      'and the server has it turned off';
}
