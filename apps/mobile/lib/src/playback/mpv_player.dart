import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// libmpv, as narrowly as this app uses it.
///
/// **One of exactly two files allowed to import `package:media_kit`**
/// (`app_no_raw_http`, `tool/check-constitution.sh`). It is pure delegation:
/// every decision — what to open, where to start, which track, when to report —
/// lives in `MediaKitPlaybackHost` and `PlayerController` over this interface,
/// so all of it is tested against `FakeMpvPlayer` with no libmpv at all.
abstract base class MpvPlayer {
  /// Allows implementations to be `const`.
  const MpvPlayer();

  /// Where playback is now.
  Stream<Duration> get position;

  /// How long the current file is.
  Stream<Duration> get duration;

  /// Whether playback is running.
  Stream<bool> get playing;

  /// Fires at the end of the file.
  Stream<bool> get completed;

  /// The tracks libmpv found, in libmpv's own shape.
  Stream<Tracks> get tracks;

  /// Whatever libmpv failed at, in its own words.
  Stream<String> get errors;

  /// Loads [media].
  Future<void> open(Media media);

  /// Resumes.
  Future<void> play();

  /// Pauses.
  Future<void> pause();

  /// Seeks.
  Future<void> seek(Duration position);

  /// Sets the volume on libmpv's own **0..100** scale.
  Future<void> setVolume(double percent);

  /// Switches audio track.
  Future<void> setAudioTrack(AudioTrack track);

  /// Switches subtitle track, [SubtitleTrack.no] for off.
  Future<void> setSubtitleTrack(SubtitleTrack track);

  /// Sets one mpv property — `tls-verify`, and nothing else today.
  Future<void> setProperty(String name, String value);

  /// The video surface, bare. Not reachable under `flutter test`.
  ///
  /// The controls that used to be built here are `PlayerControls`, which
  /// `PlayerPage` stacks over this — see `PlaybackHost.buildSurface`.
  Widget buildSurface();

  /// Releases the mpv context.
  Future<void> dispose();
}

/// What `media_kit_video` is told to draw over the picture: nothing.
///
/// **A named function rather than an inline closure**: a closure in
/// `buildSurface` is only invoked by a `Video` laying itself out, the one thing
/// that does not happen under `flutter test`.
///
/// Not the library's own `NoVideoControls`, which is `const … = null` and so
/// `dynamic`, and does not type-check against `VideoControlsBuilder?`.
/// **`Object?` rather than `VideoState`** is what makes it callable: no test
/// can construct a `State<Video>`, and parameter contravariance means
/// `Widget Function(Object?)` satisfies the typedef.
///
@visibleForTesting
Widget noLibraryControls(Object? state) => const SizedBox.shrink();

/// The real thing: one [Player], and nothing else.
final class RealMpvPlayer extends MpvPlayer {
  /// Builds a player, initialising libmpv **before** constructing it.
  factory RealMpvPlayer({String? libmpv}) {
    MediaKit.ensureInitialized(libmpv: libmpv);
    return RealMpvPlayer.over(Player());
  }

  /// Wraps an already-built [Player] — the headless suite's way in.
  RealMpvPlayer.over(this._player);

  final Player _player;
  VideoController? _controller;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Tracks> get tracks => _player.stream.tracks;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(Media media) => _player.open(media);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);

  @override
  Future<void> setAudioTrack(AudioTrack track) => _player.setAudioTrack(track);

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _player.setSubtitleTrack(track);

  @override
  Future<void> setProperty(String name, String value) =>
      (_player.platform! as NativePlayer).setProperty(name, value);

  @override
  Widget buildSurface() => Video(
    controller: _controller ??= VideoController(_player),
    pauseUponEnteringBackgroundMode: false,
    controls: noLibraryControls,
  );

  @override
  Future<void> dispose() => _player.dispose();
}
