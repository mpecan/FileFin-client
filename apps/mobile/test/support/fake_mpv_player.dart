import 'dart:async';

import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// An `MpvPlayer` with no libmpv behind it.
///
/// This is what makes `MediaKitPlaybackHost` — the file that holds every
/// translation decision — ordinary testable code. Argument-aware for the reason
/// `FakeLibraryApi` is: a fake that only counted calls could not tell
/// `SubtitleTrack.data` from `SubtitleTrack.uri`, and that difference is
/// whether the sidecar goes over the authenticated connection or libmpv's own.
final class FakeMpvPlayer extends MpvPlayer {
  /// A player that has opened nothing.
  FakeMpvPlayer();

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _tracks = StreamController<Tracks>.broadcast();
  final _errors = StreamController<String>.broadcast();

  /// Every call, in order, as `method(args)`.
  final List<String> calls = [];

  /// Every `Media` handed to [open].
  final List<Media> opened = [];

  /// Every subtitle track selected.
  final List<SubtitleTrack> subtitles = [];

  /// Every audio track selected.
  final List<AudioTrack> audio = [];

  /// Every property set, as `name=value`.
  final List<String> properties = [];

  /// Every volume set, on libmpv's own 0..100 scale.
  final List<double> volumes = [];

  /// Whether [dispose] has been called.
  bool disposed = false;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<Tracks> get tracks => _tracks.stream;

  @override
  Stream<String> get errors => _errors.stream;

  /// Pushes a track list, in libmpv's own shape.
  void emitTracks(Tracks value) => _tracks.add(value);

  /// Pushes a position tick.
  void emitPosition(Duration value) => _position.add(value);

  /// Pushes the duration.
  void emitDuration(Duration value) => _duration.add(value);

  /// Pushes a play/pause change.
  void emitPlaying({required bool value}) => _playing.add(value);

  /// Pushes end-of-file.
  void emitCompleted() => _completed.add(true);

  /// Pushes an error in libmpv's words.
  void emitError(String message) => _errors.add(message);

  @override
  Future<void> open(Media media) async {
    calls.add('open(${media.uri})');
    opened.add(media);
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek(${position.inMilliseconds}ms)');

  @override
  Future<void> setVolume(double percent) async {
    calls.add('setVolume($percent)');
    volumes.add(percent);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    calls.add('setAudioTrack(${track.id})');
    audio.add(track);
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    calls.add('setSubtitleTrack(${track.id})');
    subtitles.add(track);
  }

  @override
  Future<void> setProperty(String name, String value) async {
    calls.add('setProperty($name=$value)');
    properties.add('$name=$value');
  }

  @override
  Widget buildSurface({
    VoidCallback? onBack,
    VoidCallback? onShowSubtitles,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    String? title,
  }) {
    calls.add('buildSurface');
    return const SizedBox(key: ValueKey('fake-mpv-surface'));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    calls.add('dispose');
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
    await _tracks.close();
    await _errors.close();
  }
}
