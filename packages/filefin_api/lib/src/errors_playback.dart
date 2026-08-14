part of 'errors.dart';

/// A `415`: this file needs transcoding and the server has it turned off.
///
/// **The wording is the whole reason this variant exists.** It asks
/// that a 415 be explained as "transcoding is disabled on the server and this
/// file needs it", never as "playback failed" — so it cannot be
/// `ServerFailure`, whose message is exactly the sentence to avoid.
///
/// It is **not retryable**, only one of upstream's two 415s can reach a client,
/// and a `HEAD` 415 arrives with an empty body — which is why there is no
/// `body` field. All three measured; see `docs/field-notes.md`.
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
