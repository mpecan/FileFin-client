import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:meta/meta.dart';

/// F14's platform half, behind [NowPlayingHost].
///
/// **The only file in this package that may import `audio_service`**, exactly
/// as `media_kit_playback_host.dart` is the only one that may import
/// `media_kit`. Nothing above it knows a `MediaItem` from a `PlaybackState`.
///
/// What E-6 measured this arrangement doing, on an Android emulator at API 37:
/// a backgrounded player goes from `mutedState:opControlAudio` — the OS's
/// AppOps `CONTROL_AUDIO` restriction, which silences a background app — to
/// `mutedState:none`, and `KEYCODE_MEDIA_PAUSE` arrives in Dart. On iOS
/// `UIBackgroundModes: audio` is what stops the process being suspended, and
/// libmpv sets `AVAudioSessionCategoryPlayback` itself. `docs/risks.md` R3
/// carries both, with their negative controls.
final class AudioServiceNowPlaying implements NowPlayingHost {
  /// Wraps the handler [openNowPlaying] built.
  AudioServiceNowPlaying(this._handler);

  final FileFinAudioHandler _handler;

  @override
  Stream<TransportCommand> get commands => _handler.commands;

  @override
  Future<void> publish(NowPlayingItem metadata) async => _handler.mediaItem.add(
    MediaItem(
      // One session at a time, so the id is a constant rather than the
      // `MediaId`: nothing on the platform side ever addresses it, and a
      // real media id crossing this boundary would be one more place a
      // library identifier can leak into an OS notification.
      id: 'filefin',
      title: metadata.title,
      artist: metadata.subtitle.isEmpty ? null : metadata.subtitle,
      // Zero before the engine knows, and a zero-length item makes the
      // lock screen draw a scrubber that cannot move. Null is the
      // platform's own "unknown".
      duration: metadata.duration == Duration.zero ? null : metadata.duration,
    ),
  );

  @override
  Future<void> update(NowPlayingTransport playback) async =>
      _handler.playbackState.add(
        PlaybackState(
          controls: [
            if (playback.playing) MediaControl.pause else MediaControl.play,
          ],
          systemActions: const {MediaAction.seek},
          processingState: AudioProcessingState.ready,
          playing: playback.playing,
          updatePosition: playback.position,
        ),
      );

  @override
  Future<void> clear() async =>
      // Every field of the default is what an ended session should say —
      // `idle`, not playing, no controls — and the redundant-argument lint
      // is fatal here, so it is spelled as the default rather than restated.
      //
      // Publishing `idle` is ALSO what takes the Android foreground
      // notification down: `_observePlaybackState` calls `stopService` on the
      // transition into it (`audio_service.dart:1131-1134`). Doing it that way
      // rather than reaching for a stop method is what keeps the command
      // stream open for the next player screen — the session is per PROCESS,
      // not per screen.
      _handler.playbackState.add(PlaybackState());
}

/// Where the OS's transport buttons arrive.
///
/// `BaseAudioHandler` implements the thirty-odd callbacks the platform can
/// make; the three overridden here are the three [NowPlayingBinder] can
/// honour. The rest keep its no-op bodies, which is the point of extending it
/// rather than implementing `AudioHandlerCallbacks` — thirty empty methods
/// would be thirty dead branches (§5).
final class FileFinAudioHandler extends BaseAudioHandler {
  final _commands = StreamController<TransportCommand>.broadcast();

  /// Every transport button the OS pressed, in our own vocabulary.
  Stream<TransportCommand> get commands => _commands.stream;

  @override
  Future<void> play() async => _commands.add(const ResumeCommand());

  @override
  Future<void> pause() async => _commands.add(const PauseCommand());

  @override
  Future<void> seek(Duration position) async =>
      _commands.add(SeekCommand(position));

  /// The OS's own Stop — a swipe-away on Android, a headset stop button.
  ///
  /// Mapped to a pause rather than left as `BaseAudioHandler`'s no-op, because
  /// a stop nothing acts on leaves audio playing under a notification the user
  /// has just dismissed. It is deliberately NOT a fourth command: this app has
  /// no "stop", and leaving the screen is what ends a session.
  @override
  Future<void> stop() async => _commands.add(const PauseCommand());
}

/// Starts the OS session and returns the port bound to it (F14).
///
/// A top-level function rather than a constructor because `AudioService.init`
/// is a one-shot global — it `assert`s on a second call — so `main()` hands
/// this down as a tear-off and only a player screen ever invokes it.
///
/// **Memoised, and that is the whole reason it is a function with state rather
/// than a constructor.** A second player screen calling `init` again crashes a
/// debug build on that assert and silently re-registers the callbacks in a
/// release one. The memo makes the session per PROCESS, which is also what it
/// is on both platforms: there is one lock screen.
Future<NowPlayingHost>? _session;

/// Starts the process's one media session, or returns the one already open.
Future<NowPlayingHost> openNowPlaying() => _session ??= _openSession();

Future<NowPlayingHost> _openSession() async => AudioServiceNowPlaying(
  await AudioService.init(
    builder: FileFinAudioHandler.new,
    cacheManager: const NoArtworkCache(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.filefin.playback',
      androidNotificationChannelName: 'Playback',
      // The notification is the foreground service's, so it must not be
      // swipeable: dismissing it would stop the service and, with it, the
      // audio the user is listening to.
      androidNotificationOngoing: true,
    ),
  ),
);

/// The artwork cache F14 declines to have (§1).
///
/// `AudioService.init` builds a `DefaultCacheManager()` when it is handed
/// none, and that opens a sqflite database and an `HttpClient` for fetching
/// `MediaItem.artUri`. **We never publish one**, and could not: the poster
/// route is behind `s.auth` and the platform fetches an artwork URI itself,
/// unauthenticated, so the choice is between showing nothing and handing the
/// session cookie to a request we do not control.
///
/// Every method throws rather than returning an empty answer, so if a future
/// change ever does set an `artUri` it fails loudly here instead of silently
/// drawing no picture.
///
/// Public only so that `audio_service_now_playing_test.dart` can prove all
/// eleven of those throws; nothing outside this library constructs one.
@visibleForTesting
final class NoArtworkCache implements BaseCacheManager {
  /// The cache that is not there.
  const NoArtworkCache();

  // `Never` rather than the declared return types, and it is what keeps
  // `package:file` and `FileInfo` out of this package's imports entirely:
  // `Never` is a subtype of every one of them.
  Never get _declined => throw UnsupportedError(
    'F14 publishes no artwork, so no artwork cache exists. See '
    'audio_service_now_playing.dart.',
  );

  @override
  Future<Never> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async => _declined;

  @override
  Stream<Never> getFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) => _declined;

  @override
  Stream<Never> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool? withProgress,
  }) => _declined;

  @override
  Future<Never> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async => _declined;

  @override
  Future<Never> getFileFromCache(String key, {bool ignoreMemCache = false}) =>
      _declined;

  @override
  Future<Never> getFileFromMemory(String key) => _declined;

  @override
  Future<Never> putFile(
    String url,
    covariant Object fileBytes, {
    String? key,
    String? eTag,
    // `Duration()` rather than the interface's own 30-day default, and it is
    // the answer to a mutant rather than a preference: nothing here reads it,
    // so `30` -> `-30` is an equivalent mutant no assertion can kill. A
    // literal that means nothing is better removed than excluded.
    Duration maxAge = Duration.zero,
    String fileExtension = 'file',
  }) async => _declined;

  @override
  Future<Never> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    // `Duration()` rather than the interface's own 30-day default, and it is
    // the answer to a mutant rather than a preference: nothing here reads it,
    // so `30` -> `-30` is an equivalent mutant no assertion can kill. A
    // literal that means nothing is better removed than excluded.
    Duration maxAge = Duration.zero,
    String fileExtension = 'file',
  }) async => _declined;

  @override
  Future<void> removeFile(String key) async => _declined;

  @override
  Future<void> emptyCache() async => _declined;

  @override
  Future<void> dispose() async => _declined;
}
