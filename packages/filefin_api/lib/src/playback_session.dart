import 'package:meta/meta.dart';

/// The HTTP headers libmpv must send to play this server's bytes.
///
/// **One value type rather than a bare `Map<String, String>`, and the name is
/// chosen so a gate watches it.** `secret_tostring`
/// (`tool/check-constitution.sh`, §9) looks at every class whose name matches
/// `Session`, so this type's redacting `toString` is enforced by a check rather
/// than by a reviewer noticing — and what it holds is the session cookie, which
/// is exactly the kind of value that ends up in a log line the day someone
/// interpolates the request they were debugging.
///
/// SPEC.md §5.3 is the whole mechanism: `Media(url, httpHeaders: …)` hands
/// these straight to libmpv, which preserves them across the 307 to HLS and
/// onto every segment (R1, retired 2026-08-08).
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

  /// Prints the header **names** and none of the values (§9, NF4).
  ///
  /// The names are worth printing — "did it carry a Cookie at all?" is the
  /// first question anyone debugging playback asks — and the values never are.
  @override
  String toString() =>
      'PlaybackSessionHeaders(${_headers.keys.join(', ')}: <redacted>)';
}
