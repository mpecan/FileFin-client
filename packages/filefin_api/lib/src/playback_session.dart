import 'package:meta/meta.dart';

/// The HTTP headers libmpv must send to play this server's bytes.
///
/// **One value type rather than a bare `Map`, and the name is chosen so a gate
/// watches it**: `secret_tostring` matches every class named `*Session*`,
/// so the redacting `toString()` is enforced rather than remembered — and what
/// this holds is the session cookie.
///
/// is the mechanism: `Media(url, httpHeaders: …)` hands these to
/// libmpv, which preserves them across the 307 and onto every segment.
@immutable
class PlaybackSessionHeaders {
  /// Wraps the headers a playback request must carry.
  const PlaybackSessionHeaders(this._headers);

  final Map<String, String> _headers;

  /// The headers, as `Media`'s `httpHeaders` wants them.
  ///
  /// Unmodifiable, so a caller cannot add a header this package never agreed
  /// to send alongside a credential it did not mint.
  Map<String, String> get headers => Map.unmodifiable(_headers);

  @override
  bool operator ==(Object other) =>
      other is PlaybackSessionHeaders &&
      other._headers.length == _headers.length &&
      other._headers.entries.every((e) => _headers[e.key] == e.value);

  @override
  int get hashCode => Object.hashAll([
    for (final key in _headers.keys.toList()..sort()) '$key=${_headers[key]}',
  ]);

  /// Prints the header **names** and none of the values.
  ///
  /// The names are worth printing — "did it carry a Cookie at all?" is the
  /// first question anyone debugging playback asks — and the values never are.
  @override
  String toString() =>
      'PlaybackSessionHeaders(${_headers.keys.join(', ')}: <redacted>)';
}
