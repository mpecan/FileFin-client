import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/playback/subtitle_repair.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/widgets.dart';

// A `part` rather than a second library, for the reason `client_playback.dart`
// is one: this file reached `file-size`'s 600-line HARD limit when M5.R
// threaded a `CancelToken` through `_open`, and a gate warning may fall or hold
// and never rise. Splitting by subject keeps both halves readable and — because
// it is a part — costs no import churn at the call sites that already take
// `describeApiFailure` and `PlaybackOutcome` from here.
part 'player_failure.dart';

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

  /// NF5's token for every request this controller makes.
  ///
  /// The pre-flight made the window worth closing: `_open` awaits up to three
  /// round trips before it reaches `host.open`, and backing out of the route
  /// in that window used to resume into `host.open()` on a `Player` that
  /// `dispose` had already torn down — measured as
  /// `after gate: opened=1 calls=[dispose, open(…), play]`.
  final CancelToken _work = CancelToken();

  FileIndex _current;
  FileIndex? _engineFile;
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
  PlaybackTrackRef? _audio;
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
    // `lastSent` is set only after a `204`, so this is "the server accepted
    // something" rather than "the player tried". A session that opened and
    // closed without reaching a reporting trigger must not reload the home
    // rows, because nothing re-stamped `updated`.
    wrote: _reporter.lastSent != null,
  );

  /// Whether there is another file after this one (F7's Next).
  bool get hasNext => _current.value + 1 < detail.files.length;

  /// Whether there is a file before this one.
  bool get hasPrevious => _current.value > 0;

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

  /// Goes back to the previous file, at zero.
  Future<void> previous() async {
    if (!hasPrevious) return;
    await _reportNow(ProgressEvent.stop);
    _switchTo(FileIndex(_current.value - 1));
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
  ///
  /// Neither is sufficient **either**, and [_engineOwnsCurrent] is why: both
  /// assume the open that follows reaches `host.open`. When it does not — a
  /// refused pre-flight, a `playbackHeaders` throw — the engine keeps emitting
  /// the *old* file's events, which re-arm exactly what was just disarmed. A
  /// position tick sets `_positionIsCurrent`, a duration tick refills
  /// `_duration`, and the pair posts the old file's seconds under the new
  /// file's index: measured after M5, file 0 running to its end posted
  /// `{"file":1,"position":100,"duration":100,"event":"ended"}` and marked an
  /// episode nobody had opened fully watched.
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

  /// The audio track the user last chose, or null before they have — what was
  /// CHOSEN, never what is playing. The engine port reports what a file
  /// contains and nothing about which track libmpv selected, so the overlay's
  /// pill says "Audio" until this is non-null rather than guessing.
  PlaybackTrackRef? get audio => _audio;

  /// Switches audio track (F7).
  Future<void> selectAudio(PlaybackTrackRef track) {
    _audio = track;
    _notify();
    return host.selectAudioTrack(track);
  }

  /// Switches subtitle track, or turns them off (F7).
  Future<void> selectSubtitle(SubtitleSource? source) async {
    _subtitle = source;
    _notify();
    await host.selectSubtitleTrack(source);
  }

  /// NF6 and F14: the OS is taking the app away.
  ///
  /// **It reports and does NOT pause, and the change of mind is M7.6's.**
  /// Reporting here is still the only thing that survives an OS kill — nothing
  /// else runs afterwards — so the pointer written here is what the user comes
  /// back to. The pause that used to accompany it was NF6 read as "playback
  /// stops and resumes where it was", and F14 says the opposite: audio
  /// continues, because that is what a lock-screen transport is *for*.
  ///
  /// E-6 measured both halves of what makes that possible — libmpv keeps
  /// decoding on both platforms, `UIBackgroundModes: audio` stops iOS
  /// suspending the process, and Android's AppOps `CONTROL_AUDIO` mute is
  /// lifted by the foreground service `NowPlayingHost` runs
  /// (`docs/risks.md` R3). `mpv_player.dart`'s
  /// `pauseUponEnteringBackgroundMode: false` is the other half of this edit;
  /// either one alone leaves playback stopping on backgrounding.
  ///
  /// `resumed` deliberately does nothing: the engine never stopped, and a
  /// report on the way back in would only repeat the one on the way out.
  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
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
    _work.cancel();
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
  ///
  /// [mayRetry] is what stops the retry below from being a RECURSION, and it
  /// is there because of a measured hang rather than for tidiness: with the
  /// bound expressed only as a condition, `mutation_test` rewriting that
  /// condition's `||` to `&&` made every failure retry forever and the whole
  /// gate ran into its 300 s per-command timeout, three runs out of three.
  /// A gate that hangs reports nothing, so the second open is now structurally
  /// incapable of asking for a third.
  Future<void> _open({bool mayRetry = true}) async {
    _failure = null;
    _unplayable = null;
    try {
      if (file.transcode) {
        await api.requirePlayable(detail.id, _current, cancelToken: _work);
      }
      final headers = await api.playbackHeaders(cancelToken: _work);
      _subtitles = await _fetchSubtitles();
      // The screen went away while the pre-flight was in flight. Opening now
      // drives an engine `dispose` has already torn down, and subscribing to
      // it registers listeners nothing will ever cancel. Before `_listen`, so
      // neither happens.
      if (_disposed) return;
      await _listen();
      await host.open(
        PlaybackRequest(
          url: api.fileUrl(detail.id, _current),
          headers: headers.headers,
          startAt: _startAt,
          verifyTls: api.playbackTransport() == PlaybackTransport.osTrustedTls,
        ),
      );
      // After the await, not before: until `open` returns, what the engine
      // holds is still the previous file, and claiming otherwise is the whole
      // defect [_switchTo] describes.
      _engineFile = _current;
      await host.play();
      final first = _subtitles.isEmpty ? null : _subtitles.first;
      if (first != null) await selectSubtitle(first);
    } on FileFinApiException catch (e) {
      await _openFailed(e, mayRetry: mayRetry);
    }
  }

  /// An open that never reached the engine, and the two things it must do.
  ///
  /// **Silence what is still playing.** Every failure here lands *before*
  /// `host.open`, so the engine keeps decoding whatever it had — and after
  /// [next] has moved `_current`, that is audio for a file the screen no
  /// longer describes, behind a full-screen panel with no controls on it. The
  /// pause is the user-visible half of the same defect [_switchTo] names.
  ///
  /// **Then retry, once, unless the answer is permanent.** A `415` is
  /// deterministic — re-asking spends a round trip to be told the same thing —
  /// but a `ConnectionFailed` on the pre-flight is a blip, and before M5 the
  /// blip went through `host.errors` to [_recover]'s retry. Without this the
  /// player dead-ends on a banner with nothing behind it and no way back.
  /// Bounded twice over: [_retrySpent], which is the same latch [_recover]
  /// spends and which stops a second retry after a recovery has already used
  /// one; and `mayRetry`, which bounds it structurally. See [_open].
  ///
  /// The review also asked for `_positionIsCurrent = false` here, and it is
  /// deliberately absent: [_engineOwnsCurrent] already stops the old file's
  /// ticks from setting it, so it would be dead on the [next] path — and live
  /// and *wrong* on the other one, where [_recover] re-opens the file the
  /// engine still holds and `_positionIsCurrent` preserves F8's offset.
  Future<void> _openFailed(
    FileFinApiException error, {
    required bool mayRetry,
  }) async {
    if (_disposed) return;
    if (_engineFile != null) await host.pause();
    _fail(error);
    if (!mayRetry) return;
    if (error is TranscodingDisabled || _retrySpent) return;
    _retrySpent = true;
    await _open(mayRetry: false);
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
            data: repairSubtitle(
              await api.subtitleText(
                detail.id,
                _current,
                info.index,
                cancelToken: _work,
              ),
            ),
          ),
        );
      } on FileFinApiException {
        continue;
      }
    }
    return sources;
  }

  /// Whether the engine is holding the file [current] names.
  ///
  /// **The single source of truth [next]'s comment claims, made checkable.**
  /// `_engineFile` is written where the engine is handed a file and nowhere
  /// else, so an event arriving while it disagrees with `_current` describes a
  /// file this controller no longer reports on. Every listener that feeds a
  /// progress report is gated on it.
  bool get _engineOwnsCurrent => _engineFile == _current;

  Future<void> _listen() async {
    if (_subs.isNotEmpty) return;
    _subs.addAll([
      host.duration.listen((d) {
        if (!_engineOwnsCurrent) return;
        _duration = d;
        _notify();
      }),
      host.tracks.listen((t) {
        _tracks = t;
        _notify();
      }),
      host.position.listen((p) {
        if (!_engineOwnsCurrent) return;
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
        // No `_engineOwnsCurrent` here, and the absence is measured: this
        // reports `position: _duration`, which the two gates above hold at
        // zero for a file the engine does not own — `notStarted`. A third gate
        // is a branch no input can distinguish (§1); it survived the suite.
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
