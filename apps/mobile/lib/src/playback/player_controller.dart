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
  var _volume = 1.0;
  var _playing = false;
  var _positionIsCurrent = false;
  PlaybackTracks _tracks = PlaybackTracks.empty;
  var _subtitles = <SubtitleSource>[];
  SubtitleSource? _subtitle;
  PlaybackDecision? _decision;
  NetworkType? _sample;
  String? _failure;
  TranscodingDisabled? _unplayable;
  var _needsSignIn = false;
  var _retrySpent = false;
  var _disposed = false;

  /// Which file of the item is playing.
  FileIndex get current => _current;

  /// Where playback is.
  Duration get position => _position;

  /// How long the file is, or zero before the engine knows.
  Duration get duration => _duration;

  /// Whether the engine is playing.
  bool get playing => _playing;

  /// Where the volume slider is, `0.0`–`1.0`. Full until someone moves it.
  double get volume => _volume;

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

  /// The 415, when that is why nothing is playing (F12). Null otherwise.
  ///
  /// Separate from [failure] because the two drive different surfaces: an
  /// ordinary failure is a banner over a video that may still be playing,
  /// while this one means the engine was never opened and there is nothing
  /// behind the banner to see. `PlayerPage` shows a full-screen panel for it.
  TranscodingDisabled? get unplayable => _unplayable;

  /// Whether the user has to sign in again before anything else can work.
  bool get needsSignIn => _needsSignIn;

  /// Why progress reporting stopped, or null while it is running.
  ReportStop? get reportStop => _reporter.stopped;

  /// What the screen that pushed the player has to know on the way out (F9).
  PlaybackOutcome get outcome => PlaybackOutcome(
    state: _reporter.state,
    needsDetailRefetch: _reporter.needsDetailRefetch,
  );

  /// Whether there is another file after this one (F7's Next).
  bool get hasNext => _current.value + 1 < detail.files.length;

  /// The file currently playing.
  FileInfo get file => detail.files[_current.value];

  /// Takes F13's decision and, if it says so, opens the file.
  ///
  /// **The network is sampled once, here.** SPEC F13 says "before playing", and
  /// a mid-playback switch from Wi-Fi to cellular is out of scope — stated as
  /// debt rather than half-handled.
  Future<void> start() => _decideAndOpen();

  /// F13 asked again, for whichever file is now current.
  ///
  /// **`fileInfo.size` is per file and F13 is written per file**, so this runs
  /// for every file rather than only the first: a 10-byte episode 1 followed by
  /// a 9 GiB episode 2 opened with no prompt at all before [next] came through
  /// here (M4.R/P4). The *sample* stays once-per-session — that is the debt
  /// STATE.md names, and re-sampling here would quietly retire it — so the
  /// answer is memoised rather than re-taken.
  Future<void> _decideAndOpen() async {
    final decision = decide(
      file,
      _sample ??= await network.current(),
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
  ///
  /// The reset in [_switchTo] is what keeps that single source of truth
  /// honest, and it was data corruption before it existed — see there.
  Future<void> next() async {
    if (!hasNext) return;
    await _reportNow(ProgressEvent.stop);
    _switchTo(FileIndex(_current.value + 1));
    _startAt = Duration.zero;
    _notify();
    await _decideAndOpen();
  }

  /// Moves to [file], discarding everything that described the old one.
  ///
  /// **`_position` and `_duration` are keyed on `_current`**, and leaving them
  /// behind was user-visible data corruption (M4.R/P1): against real libmpv the
  /// first event after a second `open()` is deterministically `playing=false`,
  /// *before* any position or duration event, so the pause it triggers carried
  /// the finished file's seconds under the new file's index. Tapping Next at
  /// the end of an episode posted `{"file":1,"position":2.9,"duration":3}` and
  /// marked the whole show watched.
  ///
  /// Zeroing them is necessary and not sufficient, so [_positionIsCurrent]
  /// suppresses the report outright until the engine has said where the new
  /// file is: a report of second 0 is still a claim about a file nothing has
  /// measured, and it would overwrite a pointer the server already holds.
  void _switchTo(FileIndex file) {
    _current = file;
    _position = Duration.zero;
    _duration = Duration.zero;
    _positionIsCurrent = false;
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
  ///
  /// Kept here because the slider has to draw it: a `Slider` whose `value` was
  /// the literal `1` snapped its thumb back to full on the very next rebuild
  /// while mpv held the dragged value (M4.R/P6).
  Future<void> setVolume(double volume) {
    _volume = volume;
    _notify();
    return host.setVolume(volume);
  }

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

  /// Opens the current file, refusing first if the server will not serve it.
  ///
  /// **The pre-flight is the FIRST statement, and it is eager rather than a
  /// classification of a failure that already happened.** libmpv surfaces no
  /// status code, so a `415` arrives on [PlaybackHost.errors] as
  /// `Failed to open <url>.` and nothing else — measured verbatim at
  /// M5.0/E-I, over a black surface, which is the opposite of what F12 asks
  /// for. A 415 is also deterministic and permanent, so there is nothing for
  /// `_recover`'s retry to achieve; weaving a second question into that
  /// three-line function is what M4.R had to fix three defects in.
  ///
  /// **Guarded on `file.transcode`**, because SPEC §3.4 makes a 415 on the
  /// file route reachable only for a file that needs transcoding — a
  /// direct-play open would spend a round trip on a question with one possible
  /// answer. The flag is the server's own verdict and it stays `true` when
  /// transcoding is disabled (measured, M5.0/E-B), which is exactly what makes
  /// the guard fire in the case it exists for. It can be stale — the detail
  /// was fetched earlier — and that is accepted debt: a file that became
  /// direct-playable meanwhile simply answers `200` and the pre-flight passes.
  Future<void> _open() async {
    _failure = null;
    _unplayable = null;
    try {
      if (file.transcode) await api.requirePlayable(detail.id, _current);
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
        _positionIsCurrent = true;
        // Playback is demonstrably running again, so the next failure gets its
        // own retry. See [_recover].
        _retrySpent = false;
        _notify();
        unawaited(_report(ProgressEvent.checkpoint));
      }),
      host.playing.listen((p) {
        _playing = p;
        _notify();
        if (!p && _positionIsCurrent) unawaited(_report(ProgressEvent.pause));
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
  /// to sign in.
  ///
  /// **The retry is spent until playback demonstrably resumes**, which is what
  /// a position tick says and nothing else does. The guard used to latch for
  /// the controller's whole life and [message] was never read, so two things
  /// were wrong at once (M4.R/P2): a genuinely broken file gave a **black
  /// player with no text on it**, which is the opposite of what F12 asks for;
  /// and a session dying mid-film after any earlier transient error never
  /// reached `api.me()` again, so it never routed to sign-in. Spending the
  /// retry still stops the loop — a file that cannot play never ticks.
  Future<void> _recover(String message) async {
    if (_disposed) return;
    if (_retrySpent) {
      // mpv's own words. It is all there is: no status code reaches here.
      _failure = message;
      _notify();
      return;
    }
    // Set before the first await, so three errors arriving together produce
    // one retry and two messages rather than three retries.
    _retrySpent = true;
    try {
      await api.me();
      _reporter.resume();
      // Only where a tick has actually been, for the reason [_switchTo] gives:
      // `_position` describes nothing until the engine has said so, and
      // overwriting `_startAt` with it threw away F8's resume offset when the
      // very first open failed.
      if (_positionIsCurrent) _startAt = _position;
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
    _unplayable = error is TranscodingDisabled ? error : null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// What one playback session leaves behind for the screen that opened it.
///
/// **This is F9's second clause made into a value someone receives** — "reflect
/// resulting watched/continue changes locally without a full refetch". Until
/// M4.R/P3 `ProgressReporter.state` and `needsDetailRefetch` had no production
/// reader at all: the fold was computed, validated against 601 captured vectors
/// and thrown away, `MediaDetailPage` loaded once in `initState` and never
/// again, and the detail screen behind the player showed a resume offset from
/// before playback started. M1's divergence latch discharged nothing because
/// nothing read it.
@immutable
class PlaybackOutcome {
  /// The session ended with [state], needing a refetch or not.
  const PlaybackOutcome({
    required this.state,
    required this.needsDetailRefetch,
  });

  /// The optimistic watch state, folded through the server's own engine.
  final WatchState state;

  /// Whether [state] is known to have diverged and must be re-read instead.
  ///
  /// True only for the one input class `applyProgress` provably cannot match —
  /// a report crossing 90% of a single-file item, where `(0, 0)` is ambiguous
  /// on the wire. Everywhere else the prediction IS the server's answer, which
  /// is what makes the no-refetch half of F9 honest rather than optimistic.
  final bool needsDetailRefetch;
}

/// The sentence a playback failure shows, and whether it needs a sign-in.
///
/// A tuple rather than a reach into `error_presentation.dart`'s `ErrorMessage`:
/// the player shows one line over the video, not a full panel with a Retry
/// button, and the two surfaces want different things from the same error.
///
/// **There is no `_` arm, and its absence is the point.** This function had one
/// until M5.1, and it was a hole in an alarm three other switches were sounding
/// correctly: `error_presentation.dart`, `error_presentation_test.dart` and
/// `error_mapper_test.dart` all stopped compiling when `TranscodingDisabled`
/// landed and this one did not (measured, M5.0/E-J). It would have rendered
/// `Playback could not start: TranscodingDisabled: … turned off` on the player
/// banner — the surface F12 is actually about — with nothing to say so. The
/// generic sentence is now a **grouped arm** rather than a default, so it still
/// covers everything with no wording of its own while a new variant remains a
/// compile error here.
(String, bool) describeApiFailure(FileFinApiException error) => switch (error) {
  SessionExpired() => (
    'Your session ended. Sign in again to keep playing.',
    true,
  ),
  TranscodingDisabled() => (
    'This file needs transcoding and the server has it turned off.',
    false,
  ),
  BadRequest(:final body) => ('The server refused that file: $body', false),
  NotFound() => ('That file is not on the server any more.', false),
  RequestTimedOut() ||
  RequestCancelled() ||
  ConnectionFailed() ||
  CacheUnavailable() ||
  RateLimited() ||
  MalformedIdentifier() ||
  InvalidCredentials() ||
  NotAFileFinServerResponse() ||
  MalformedResponse() ||
  ServerFailure() ||
  CertificateNotTrusted() ||
  CertificatePinMismatch() => ('Playback could not start: $error', false),
};
