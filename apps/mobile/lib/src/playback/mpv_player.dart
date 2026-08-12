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
/// **A named function rather than an inline closure**, because a closure inside
/// `buildSurface` is only ever invoked by a `Video` laying itself out — which
/// is the one thing that does not happen under `flutter test` — so the app's
/// decision to decline the library's transport was a line no test could reach.
///
/// It is not the library's own `NoVideoControls`, which is `const … = null` and
/// therefore `dynamic`: passing it does not type-check against
/// `VideoControlsBuilder?`. Either way the library draws no transport of its
/// own, because `PlayerControls` is the app's overlay and two sets of buttons
/// over one video is two things to tap and one of them wrong.
///
/// **`Object?` rather than `VideoState`**, and that is what makes it callable:
/// a `VideoState` is a `State<Video>` a test has no way to construct, while
/// Dart's function subtyping is contravariant in its parameters — so a
/// `Widget Function(Object?)` satisfies `VideoControlsBuilder` and takes a
/// `null` from a test. The argument is ignored either way.
///
/// Public only so a test can reach it; nothing outside this library calls it
/// (§5, `public_member_no_consumer`).
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
