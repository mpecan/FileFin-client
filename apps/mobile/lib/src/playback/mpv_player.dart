import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// libmpv, as narrowly as this app uses it.
///
/// **One of exactly two files allowed to import `package:media_kit`**
/// (`app_no_raw_http`, `tool/check-constitution.sh`). It is pure delegation:
/// every decision — what to open, where to start, which track, when to report —
/// lives in `MediaKitPlaybackHost` and `PlayerController` over this interface,
/// so all of it is tested against `FakeMpvPlayer` with no libmpv at all.
///
/// [buildSurface] is here rather than in the host, and that placement is a
/// measurement rather than a preference: `VideoController(player)` **hangs**
/// under `flutter test` — it awaits a platform channel `flutter_tester` does
/// not host, and a probe that pumped a `Video` never returned (M4.0, killed at
/// five minutes). Keeping it in this file confines the one genuinely
/// uncoverable expression in the milestone to the file that is already the
/// thinnest, instead of putting it in the middle of the translation logic.
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

  /// Switches subtitle track, `SubtitleTrack.no()` for off.
  Future<void> setSubtitleTrack(SubtitleTrack track);

  /// Sets one mpv property — `tls-verify`, and nothing else today.
  Future<void> setProperty(String name, String value);

  /// The video surface. Not reachable under `flutter test` — see the class doc.
  Widget buildSurface();

  /// Releases the mpv context.
  Future<void> dispose();
}

/// The real thing: one `Player`, and nothing else.
final class RealMpvPlayer extends MpvPlayer {
  /// Builds a player, initialising libmpv **before** constructing it.
  ///
  /// A factory rather than a generative constructor, and that ordering is the
  /// reason: a field initialiser runs before the constructor body, so
  /// `_player = Player()` with `ensureInitialized()` in the body would build
  /// the player before libmpv was loaded.
  ///
  /// [libmpv] is normally null. On a device the prebuilt `media_kit_libs_*`
  /// framework is what `ensureInitialized` resolves, and hard-coding a path
  /// here would be hard-coding a developer's Homebrew install; the headless
  /// suite passes one because `media_kit`'s macOS default-name list is
  /// `['Mpv.framework/Mpv']` and nothing else (measured, M4.0/E2b).
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

  /// The texture libmpv draws into.
  ///
  /// **`pauseUponEnteringBackgroundMode` is `false` and that is F14's whole
  /// Android half.** The argument DEFAULTS TO TRUE
  /// (`video_texture.dart:132`), and on `AppLifecycleState.paused` the widget
  /// calls `player.pause()` itself (`:281-299`) — so until M7.6 every
  /// backgrounding stopped playback inside `media_kit_video`, before the OS
  /// had any say. Measured both ways at M7.6/E-6: with the default, position
  /// froze at 18941 ms for the whole 60 s background window; with it off,
  /// position advanced 1:1 with the wall clock (`docs/risks.md` R3).
  ///
  /// `resumeUponEnteringForegroundMode` is left at its own default of `false`
  /// and is now correct rather than merely unset: nothing pauses on
  /// backgrounding any more, so there is nothing to resume.
  @override
  Widget buildSurface() => Video(
    controller: _controller ??= VideoController(_player),
    pauseUponEnteringBackgroundMode: false,
  );

  @override
  Future<void> dispose() => _player.dispose();
}
