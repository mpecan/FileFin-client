import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/widgets.dart';

/// Drives one playing item: F7, F8, F9, F13, NF6 and playback's half of F3.
///
/// **A `ChangeNotifier`, deliberately not an `AsyncController`.** That one is
/// one-shot-fetch shaped and cancels its work on dispose, which is exactly
/// right for a screen that loads a list and wrong for a player: this is a
/// long-lived state machine that opens files, advances between them, survives
/// a backgrounding and has a final report to make on the way out.
///
/// Every policy it consults is a pure function in `filefin_core` — `decide`,
/// `decideReport`, `startSecondsFor` — so what is left here is sequencing, and
/// sequencing is what a widget test can drive.
class PlayerController extends ChangeNotifier {
  /// Plays [detail] through [host], starting at [initialFile].
  PlayerController({
    required this.api,
    required this.host,
    required this.network,
    required this.detail,
    required this.server,
    required this.prefs,
    required FileIndex initialFile,
    required Duration startAt,
  }) : _current = initialFile,
       _startAt = startAt,
       _reporter = ProgressReporter(
         api: api,
         media: detail.id,
         intervalSecs: prefs.progressIntervalSecs,
         fileCount: detail.files.length,
         initial: WatchState.fromDetail(detail),
       );

  /// The authenticated client. The **only** thing that knows what a 401 is.
  final LibraryApi api;

  /// The engine. One per screen, disposed with it.
  final PlaybackHost host;

  /// F13's sample, taken once at [start].
  final NetworkStatus network;

  /// The item being played.
  final MediaDetail detail;

  /// The saved server, for its per-server playback settings.
  final SavedServer server;

  /// The settings that are not per server.
  final PlaybackPrefs prefs;

  final ProgressReporter _reporter;
  final List<StreamSubscription<Object?>> _subs = [];

  FileIndex _current;
  Duration _startAt;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  var _playing = false;
  PlaybackTracks _tracks = PlaybackTracks.empty;
  var _subtitles = <SubtitleSource>[];
  SubtitleSource? _subtitle;
  PlaybackDecision? _decision;
  String? _failure;
  var _needsSignIn = false;
  var _recovering = false;
  var _disposed = false;

  /// Which file of the item is playing.
  FileIndex get current => _current;

  /// Where playback is.
  Duration get position => _position;

  /// How long the file is, or zero before the engine knows.
  Duration get duration => _duration;

  /// Whether the engine is playing.
  bool get playing => _playing;

  /// The audio tracks the engine found (F7).
  PlaybackTracks get tracks => _tracks;

  /// The sidecar subtitles fetched for the current file.
  List<SubtitleSource> get subtitles => List.unmodifiable(_subtitles);

  /// Which subtitle is showing, or null for Off.
  SubtitleSource? get subtitle => _subtitle;

  /// [decide]'s answer, once [start] has taken it. Null before that.
  PlaybackDecision? get decision => _decision;

  /// Whatever went wrong, phrased for a person, or null.
  String? get failure => _failure;

  /// Whether the user has to sign in again before anything else can work.
  bool get needsSignIn => _needsSignIn;

  /// Why progress reporting stopped, or null while it is running.
  ReportStop? get reportStop => _reporter.stopped;

  /// Whether the detail must be re-read rather than trusted (M1's divergence).
  bool get needsDetailRefetch => _reporter.needsDetailRefetch;

  /// The optimistic watch state, folded through the server's own engine.
  WatchState get watchState => _reporter.state;

  /// Whether there is another file after this one (F7's Next).
  bool get hasNext => _current.value + 1 < detail.files.length;

  /// The file currently playing.
  FileInfo get file => detail.files[_current.value];

  /// Takes F13's decision and, if it says so, opens the file.
  ///
  /// **The network is sampled once, here.** SPEC F13 says "before playing", and
  /// a mid-playback switch from Wi-Fi to cellular is out of scope — stated as
  /// debt rather than half-handled.
  Future<void> start() async {
    final decision = decide(
      file,
      await network.current(),
      PlaybackSettings(
        wifiOnly: server.wifiOnly,
        meteredWarnBytes: prefs.meteredWarnBytes,
        progressIntervalSecs: prefs.progressIntervalSecs,
      ),
      transport: api.playbackTransport(),
      allowUnverifiedPlayback: server.allowUnverifiedPlayback,
    );
    _decision = decision;
    _notify();
    if (decision is PlayNow) await _open();
  }

  /// The user accepted F13's size prompt.
  Future<void> confirmLargeOnMetered() async {
    final decision = _decision;
    if (decision is! ConfirmLargeOnMetered) return;
    _decision = decision.proceed;
    _notify();
    await _open();
  }

  /// Advances to the next file (F7).
  ///
  /// **We advance ourselves rather than using mpv's playlist**, and the reason
  /// is that the playlist index would be a second source of truth for "which
  /// file is playing" — and that index is what every progress report is keyed
  /// on. The cost is no gapless preload, which is stated in STATE.md rather
  /// than discovered.
  Future<void> next() async {
    if (!hasNext) return;
    await _reportNow(ProgressEvent.stop);
    _current = FileIndex(_current.value + 1);
    _startAt = Duration.zero;
    _notify();
    await _open();
  }

  /// Seeks, then reports — `onChangeEnd`, never during a drag.
  Future<void> seekTo(Duration to) async {
    await host.seek(to);
    _position = to;
    _notify();
    await _report(ProgressEvent.seek);
  }

  /// Plays or pauses.
  Future<void> togglePlay() => _playing ? host.pause() : host.play();

  /// Sets the volume, `0.0`–`1.0`.
  Future<void> setVolume(double volume) => host.setVolume(volume);

  /// Switches audio track (F7).
  Future<void> selectAudio(PlaybackTrackRef track) =>
      host.selectAudioTrack(track);

  /// Switches subtitle track, or turns them off (F7).
  Future<void> selectSubtitle(SubtitleSource? source) async {
    _subtitle = source;
    _notify();
    await host.selectSubtitleTrack(source);
  }

  /// NF6: the OS is taking the app away.
  ///
  /// Pausing and reporting on `paused`/`inactive` is the only thing that
  /// survives an OS kill — nothing else runs afterwards — so the pointer
  /// written here is what the user comes back to. `resumed` deliberately does
  /// nothing: the engine kept its position, and auto-resuming would start
  /// playing in a pocket.
  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      await host.pause();
      await _reportNow(ProgressEvent.pause);
    }
  }

  /// The final report, awaited, on the way out of the route.
  Future<void> close() => _reportNow(ProgressEvent.stop);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Unawaited, as a backstop: `PopScope` awaits `close()` on the normal path,
    // and a dispose that blocked on a request would hold the frame.
    unawaited(_reportNow(ProgressEvent.stop));
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    unawaited(host.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    _failure = null;
    try {
      final headers = await api.playbackHeaders();
      _subtitles = await _fetchSubtitles();
      await _listen();
      await host.open(
        PlaybackRequest(
          url: api.fileUrl(detail.id, _current),
          headers: headers.headers,
          startAt: _startAt,
          verifyTls: api.playbackTransport() == PlaybackTransport.osTrustedTls,
        ),
      );
      await host.play();
      final first = _subtitles.isEmpty ? null : _subtitles.first;
      if (first != null) await selectSubtitle(first);
    } on FileFinApiException catch (e) {
      _fail(e);
    }
  }

  /// Fetches every sidecar for the current file **through the API**.
  ///
  /// A subtitle that fails to fetch is dropped rather than failing the open: a
  /// missing caption is not a reason to refuse to play a film, and the menu
  /// simply has one fewer row.
  Future<List<SubtitleSource>> _fetchSubtitles() async {
    final sources = <SubtitleSource>[];
    for (final info in file.subtitles) {
      try {
        sources.add(
          SubtitleSource(
            index: info.index,
            label: info.label.isEmpty ? info.lang : info.label,
            data: await api.subtitleText(detail.id, _current, info.index),
          ),
        );
      } on FileFinApiException {
        continue;
      }
    }
    return sources;
  }

  Future<void> _listen() async {
    if (_subs.isNotEmpty) return;
    _subs.addAll([
      host.duration.listen((d) {
        _duration = d;
        _notify();
      }),
      host.tracks.listen((t) {
        _tracks = t;
        _notify();
      }),
      host.position.listen((p) {
        _position = p;
        _notify();
        unawaited(_report(ProgressEvent.checkpoint));
      }),
      host.playing.listen((p) {
        _playing = p;
        _notify();
        if (!p) unawaited(_report(ProgressEvent.pause));
      }),
      host.completed.listen((done) {
        if (!done) return;
        // `position: duration` so the crossing is unambiguous: mpv's last
        // position tick can land a few milliseconds short of the end, which is
        // below the 90% threshold on a very short file.
        _position = _duration;
        _notify();
        unawaited(_report(ProgressEvent.ended));
      }),
      host.errors.listen((message) => unawaited(_recover(message))),
    ]);
  }

  /// **libmpv does not surface status codes, so we ask the layer that does.**
  ///
  /// A 401 and a missing file produce the same sentence from mpv. One `me()`
  /// separates them: if it succeeds the session was fine — or F3 has just
  /// renewed it — so re-opening once is worth a try; if it fails the user has
  /// to sign in. The flag guard is what stops a genuinely broken file from
  /// looping.
  Future<void> _recover(String message) async {
    if (_recovering || _disposed) return;
    _recovering = true;
    try {
      await api.me();
      _reporter.resume();
      _startAt = _position;
      await _open();
    } on FileFinApiException catch (e) {
      _fail(e);
    }
  }

  Future<void> _report(ProgressEvent event) => _reporter.report(
    file: _current,
    position: _position,
    duration: _duration,
    event: event,
  );

  Future<void> _reportNow(ProgressEvent event) async {
    await _report(event);
    if (!_disposed) _notify();
  }

  void _fail(FileFinApiException error) {
    final described = describeApiFailure(error);
    _failure = described.$1;
    _needsSignIn = described.$2;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// The sentence a playback failure shows, and whether it needs a sign-in.
///
/// A tuple rather than a reach into `error_presentation.dart`'s `ErrorMessage`:
/// the player shows one line over the video, not a full panel with a Retry
/// button, and the two surfaces want different things from the same error.
(String, bool) describeApiFailure(FileFinApiException error) => switch (error) {
  SessionExpired() => (
    'Your session ended. Sign in again to keep playing.',
    true,
  ),
  BadRequest(:final body) => ('The server refused that file: $body', false),
  NotFound() => ('That file is not on the server any more.', false),
  _ => ('Playback could not start: $error', false),
};
