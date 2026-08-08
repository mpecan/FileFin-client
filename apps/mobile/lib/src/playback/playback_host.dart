import 'package:filefin_core/filefin_core.dart';
import 'package:flutter/widgets.dart';

/// One selectable track, in **our** vocabulary.
///
/// [id] is whatever the engine calls it and is passed straight back on
/// selection; nothing in this app parses it. [label] is what a menu shows, and
/// it is assembled by the adapter from whatever the engine knew — a language, a
/// codec, or the id when it knew nothing.
@immutable
class PlaybackTrackRef {
  /// A track the engine calls [id], shown as [label].
  const PlaybackTrackRef({required this.id, required this.label});

  /// The engine's own identifier, opaque here.
  final String id;

  /// What the audio menu shows.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is PlaybackTrackRef && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'PlaybackTrackRef($id, $label)';
}

/// What the engine found inside the file.
///
/// **Audio only, and that is C2 (SPEC §11) narrowed rather than ignored.** The
/// API lists sidecar subtitles and nothing else — `fileInfo` has no audio array
/// at all — so F7's audio-track selection is *only* satisfiable from what
/// libmpv sees. Embedded **subtitles** stay deferred; embedded audio is used
/// because nothing else can satisfy the requirement.
@immutable
class PlaybackTracks {
  /// The audio tracks the engine can switch between.
  const PlaybackTracks({required this.audio});

  /// Nothing known yet — what a host reports before a file has opened.
  static const empty = PlaybackTracks(audio: []);

  /// Every selectable audio track, in the engine's order.
  final List<PlaybackTrackRef> audio;

  @override
  String toString() => 'PlaybackTracks(${audio.length} audio)';
}

/// One sidecar subtitle, **already fetched through the authenticated client**.
///
/// [data] is the WebVTT text, not a URL, and that is the design rather than a
/// convenience. The subtitle route sits behind `s.auth`, so handing libmpv a
/// URL would make it open its own unauthenticated, unpinned connection; reading
/// the text through `LibraryApi` keeps the cookie jar, F3's retry and F15's pin
/// on the one part of playback that can still have them.
@immutable
class SubtitleSource {
  /// The [index]-th sidecar, shown as [label], carrying [data].
  const SubtitleSource({
    required this.index,
    required this.label,
    required this.data,
  });

  /// Which sidecar this is, for the menu's selection state.
  final SubtitleIndex index;

  /// What the subtitle menu shows.
  final String label;

  /// The WebVTT text itself.
  final String data;

  @override
  String toString() =>
      'SubtitleSource(${index.value}, $label, ${data.length} chars)';
}

/// Everything the engine needs to start playing one file.
@immutable
class PlaybackRequest {
  /// Play [url] with [headers], starting at [startAt].
  const PlaybackRequest({
    required this.url,
    required this.headers,
    required this.startAt,
    required this.verifyTls,
  });

  /// The absolute URL, from `LibraryApi.fileUrl`.
  final Uri url;

  /// The headers the engine must send — the session cookie, today.
  final Map<String, String> headers;

  /// Where playback begins, from `startSecondsFor`.
  final Duration startAt;

  /// Whether the engine should verify the peer's certificate.
  ///
  /// True for [PlaybackTransport.osTrustedTls]. False for a pinned server the
  /// user has explicitly allowed (D10): turning verification on there would
  /// refuse the very certificate they accepted.
  final bool verifyTls;

  /// Prints the header **names** and none of their values (§9, NF4).
  @override
  String toString() =>
      'PlaybackRequest($url, ${headers.keys.join(', ')}: <redacted>, '
      'start ${startAt.inSeconds}s, verifyTls: $verifyTls)';
}

/// The player engine, as a port.
///
/// **This is the seam the whole milestone is built on.** `media_kit`'s core is
/// pure Dart over `dart:ffi`, so a `Player` genuinely constructs under
/// `flutter test` against a host libmpv (measured at M4.0/E2: duration, a
/// position past one second, an audio track list and a `completed` event, all
/// headless). What does **not** work headlessly is the texture — `vo=null`
/// rasterises nothing and `VideoController` needs a platform channel
/// `flutter_tester` does not host.
///
/// So [buildSurface] is on the port precisely so that no widget test ever
/// builds `media_kit_video`'s `Video`. A fake host returns a coloured box and
/// every screen test runs; the real one is exercised by `test_live/` and, for
/// the pixels, by `docs/verification-backlog.md` row 15.
///
/// `abstract base class`, following `LibraryApi` and `SecretStore`: `base`
/// forces subtypes to `extend`, so a method added here is a compile error in
/// every implementation rather than something an `implements` clause satisfies
/// with a silent stub.
abstract base class PlaybackHost {
  /// Allows implementations to be `const`.
  const PlaybackHost();

  /// Where playback is now. The trigger for every checkpoint report (F9).
  Stream<Duration> get position;

  /// How long the file is. `Duration.zero` until the engine knows.
  Stream<Duration> get duration;

  /// Whether the engine is playing. `false` drives the `pause` report.
  Stream<bool> get playing;

  /// Fires `true` at the end of the file, driving the `ended` report.
  Stream<bool> get completed;

  /// What the engine found inside the file (F7's audio menu).
  Stream<PlaybackTracks> get tracks;

  /// Whatever the engine failed at, in its own words.
  ///
  /// **A `String`, and deliberately not a status code.** libmpv does not
  /// surface one: a 401 arrives as `Failed to open <url>` and so does a missing
  /// file. `PlayerController` answers that by asking the layer that *does* know
  /// — one `me()` round trip — rather than by parsing this.
  Stream<String> get errors;

  /// Loads [request] and seeks to its start position.
  Future<void> open(PlaybackRequest request);

  /// Resumes.
  Future<void> play();

  /// Pauses.
  Future<void> pause();

  /// Seeks to [position].
  Future<void> seek(Duration position);

  /// Sets the volume, `0.0` to `1.0`.
  Future<void> setVolume(double volume);

  /// Switches to [track], one of the refs [tracks] reported.
  Future<void> selectAudioTrack(PlaybackTrackRef track);

  /// Shows [source], or turns subtitles off when it is null.
  Future<void> selectSubtitleTrack(SubtitleSource? source);

  /// The widget that renders the video.
  Widget buildSurface();

  /// Releases the engine. One host per player screen, disposed with it.
  Future<void> dispose();
}
