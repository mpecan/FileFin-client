import 'dart:async';

import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter/widgets.dart';

/// A `PlaybackHost` a widget test can drive without libmpv.
///
/// **Argument-aware, for the reason `FakeLibraryApi` is** (M3's review): a fake
/// that only counts calls cannot tell a seek to 42 seconds from a seek to 0,
/// and "which file is playing" is what every progress report is keyed on. Every
/// call is recorded verbatim in [calls] and the payloads that matter are kept
/// as objects in [opened] and [seeks].
///
/// The streams are broadcast controllers a test pushes into, so a whole
/// playback session — open, position ticks, a pause, completion — is written as
/// a sequence of `emit` calls with no clock and no timer anywhere.
final class FakePlaybackHost extends PlaybackHost {
  /// A host that has opened nothing.
  FakePlaybackHost();

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _tracks = StreamController<PlaybackTracks>.broadcast();
  final _errors = StreamController<String>.broadcast();

  /// Every call made, in order, as `method(args)`.
  final List<String> calls = [];

  /// Every request handed to [open], in order.
  final List<PlaybackRequest> opened = [];

  /// Every position handed to [seek], in order.
  final List<Duration> seeks = [];

  /// Every subtitle selection, `null` meaning Off.
  final List<SubtitleSource?> subtitles = [];

  /// What [buildSurface] returns, so a screen test can find it.
  Widget surface = const SizedBox(key: ValueKey('fake-surface'));

  /// Set to throw from [open], for the failure arms.
  Object? openFailure;

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
  Stream<PlaybackTracks> get tracks => _tracks.stream;

  @override
  Stream<String> get errors => _errors.stream;

  /// Pushes a position tick.
  void emitPosition(Duration value) => _position.add(value);

  /// Pushes the file's duration.
  void emitDuration(Duration value) => _duration.add(value);

  /// Pushes a play/pause change.
  void emitPlaying({required bool value}) => _playing.add(value);

  /// Pushes end-of-file.
  void emitCompleted() => _completed.add(true);

  /// Pushes a track list.
  void emitTracks(PlaybackTracks value) => _tracks.add(value);

  /// Pushes an engine error, in the engine's own words.
  void emitError(String message) => _errors.add(message);

  @override
  Future<void> open(PlaybackRequest request) async {
    calls.add('open($request)');
    opened.add(request);
    final failure = openFailure;
    if (failure != null) {
      // A field holding whatever the real host threw, which is deliberately
      // not always an Error: `open` can fail with a FileFinApiException.
      // ignore: only_throw_errors
      throw failure;
    }
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek(${position.inMilliseconds}ms)');
    seeks.add(position);
  }

  @override
  Future<void> setVolume(double volume) async =>
      calls.add('setVolume($volume)');

  @override
  Future<void> selectAudioTrack(PlaybackTrackRef track) async =>
      calls.add('selectAudioTrack(${track.id})');

  @override
  Future<void> selectSubtitleTrack(SubtitleSource? source) async {
    calls.add('selectSubtitleTrack(${source?.index.value})');
    subtitles.add(source);
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
    return surface;
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
