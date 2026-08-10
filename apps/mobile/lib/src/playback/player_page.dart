import 'dart:async';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/file_list.dart' show humanSize;
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'player_panels.dart';

/// The player screen (F7, F8, F9, F13, NF6).
///
/// Opens in landscape and uses mpv's on-screen controls (OSC) rather than
/// drawing its own. The OSC is drawn by libmpv itself onto the video surface,
/// so there is exactly one set of controls and they are always in the right
/// place.
class PlayerPage extends StatefulWidget {
  /// Plays [detail]'s [initialFile], starting [startAt] seconds in.
  const PlayerPage({
    required this.api,
    required this.hostFactory,
    required this.nowPlayingFactory,
    required this.network,
    required this.detail,
    required this.server,
    required this.prefs,
    required this.initialFile,
    required this.startAt,
    this.onSignIn,
    super.key,
  });

  /// Where progress, sidecars and the session cookie come from.
  final LibraryApi api;

  /// **A factory, not an instance.** One engine per screen, disposed with it;
  /// two screens sharing an mpv context would share a position.
  final PlaybackHost Function() hostFactory;

  /// Opens F14's media session. Per process rather than per screen — see
  /// `AppDependencies.nowPlayingFactory`.
  final Future<NowPlayingHost> Function() nowPlayingFactory;

  /// F13's sample.
  final NetworkStatus network;

  /// The item being played.
  final MediaDetail detail;

  /// The saved server, for its per-server playback settings.
  final SavedServer server;

  /// The settings that are not per server.
  final PlaybackPrefs prefs;

  /// Which file to open.
  final FileIndex initialFile;

  /// Where to start, from `startSecondsFor`.
  final Duration startAt;

  /// Where a dead session sends the user.
  final VoidCallback? onSignIn;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerController _controller = PlayerController(
    api: widget.api,
    host: widget.hostFactory(),
    network: widget.network,
    detail: widget.detail,
    server: widget.server,
    prefs: widget.prefs,
    initialFile: widget.initialFile,
    startAt: widget.startAt,
  );
  AppLifecycleListener? _lifecycle;
  NowPlayingBinder? _binder;
  var _gone = false;
  var _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    // Constructed eagerly rather than lazily: an `AppLifecycleListener` that
    // nothing has touched has not registered with the binding, so NF6's
    // report — the only thing that survives an OS kill — would never fire.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => unawaited(_controller.handleLifecycle(state)),
    );
    _controller.addListener(_onChange);
    unawaited(_bindSession());
    unawaited(_controller.start());
  }

  /// Locks the screen to landscape and hides the system UI.
  ///
  /// The system UI is restored in [dispose] so leaving the player doesn't
  /// strand the rest of the app in fullscreen.
  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// F14: attaches the lock-screen transport to this player.
  ///
  /// Unawaited and out of band, because starting the session is a platform
  /// round trip and playback must not wait on it — a media session that fails
  /// to start is a lock screen with no controls, not a film that will not
  /// play.
  ///
  /// Which is exactly why the `_gone` arm exists: the user can leave during
  /// that round trip, and binding afterwards would publish metadata for a
  /// controller `dispose` has already torn down and leave a transport
  /// notification with nothing behind it.
  ///
  /// **A start that fails is caught here and nowhere else could catch it.**
  /// This is invoked `unawaited(...)` from `initState`, so a throw is an
  /// unhandled async error with no handler above it — and there is nothing to
  /// retry either: `AudioService.init` asserts on a second call
  /// (`audio_service.dart:1007`) and sets the flag it asserts on before the
  /// platform call that can fail, so `openNowPlaying`'s memo is right to keep
  /// a failure. What the user gets is a lock screen with no controls, which is
  /// what the sentence above promises.
  Future<void> _bindSession() async {
    final NowPlayingHost session;
    try {
      session = await widget.nowPlayingFactory();
    } on Object {
      return;
    }
    if (_gone) {
      await session.clear();
      return;
    }
    _binder = NowPlayingBinder(session: session, controller: _controller);
  }

  void _toggleControls() {
    _hideTimer?.cancel();
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
    } else {
      setState(() => _controlsVisible = true);
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gone = true;
    _restoreOrientations();
    unawaited(_binder?.dispose());
    _lifecycle?.dispose();
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  /// Restores the system's own orientation policy and normal UI.
  ///
  /// An empty list means "no preference" — the device's auto-rotate setting
  /// decides, exactly as it did before the player opened. Explicitly passing
  /// [DeviceOrientation.values] would force all orientations on, which reads
  /// as "this app turned auto-rotate back on" to someone who had it off.
  void _restoreOrientations() {
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => PopScope<PlaybackOutcome>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      await _controller.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      if (context.mounted) Navigator.of(context).pop(_controller.outcome);
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: _body(),
    ),
  );

  Widget _body() {
    final decision = _controller.decision;
    if (decision is Refuse) {
      return _RefusalPanel(reason: decision.reason, server: widget.server);
    }
    if (decision is ConfirmLargeOnMetered) {
      return MeteredPrompt(
        bytes: decision.bytes,
        onConfirm: () => unawaited(_controller.confirmLargeOnMetered()),
        onCancel: () => Navigator.of(context).maybePop(),
      );
    }
    if (_controller.unplayable != null) {
      return _UnplayablePanel(server: widget.server);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // The video fills the screen. A tap toggles both mpv's OSC and our
        // overlay controls together, so they appear and disappear as one.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleControls,
          child: _controller.host.buildSurface(),
        ),
        // Banners overlaid on top of the video rather than shunting it down.
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.api.playbackTransport() ==
                        PlaybackTransport.pinnedTls &&
                    widget.server.allowUnverifiedPlayback)
                  const UnverifiedTlsBanner(),
                if (_controller.failure != null)
                  _FailureBanner(
                    message: _controller.failure!,
                    onSignIn: _controller.needsSignIn ? widget.onSignIn : null,
                  ),
                if (_controller.reportStop == ReportStop.rejected)
                  const _ReportStoppedBanner(),
              ],
            ),
          ),
        ),
        // Overlaid controls for what mpv's OSC does not surface. Shown and
        // hidden together with the OSC on a tap.
        if (_controlsVisible)
          SafeArea(child: _OverlayControls(controller: _controller)),
      ],
    );
  }
}

/// Buttons overlaid on the video for next, previous, subtitles and back.
///
/// mpv's OSC handles play/pause, seek and volume. This overlay adds the
/// transport controls mpv cannot know about: navigating between episodes,
/// switching subtitles, and leaving the player.
class _OverlayControls extends StatelessWidget {
  const _OverlayControls({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
    );
    final deco = BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(20),
    );
    return Stack(
      children: [
        // Back — top left
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: deco,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        // Subtitles — top right, shown only when sidecars exist
        if (controller.subtitles.isNotEmpty)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: deco,
              child: _SubtitleButton(controller: controller),
            ),
          ),
        // Next episode — bottom center
        if (controller.hasNext)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: deco,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: controller.next,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Next', style: style),
                        SizedBox(width: 4),
                        Icon(Icons.skip_next, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A dropdown that switches between available subtitles.
class _SubtitleButton extends StatelessWidget {
  const _SubtitleButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.subtitles, color: Colors.white),
    tooltip: 'Subtitles',
    color: Colors.black87,
    onSelected: (label) {
      final sub = controller.subtitles.cast<SubtitleSource?>().firstWhere(
        (s) => s?.label == label,
        orElse: () => null,
      );
      controller.selectSubtitle(sub);
    },
    itemBuilder: (_) => [
      const PopupMenuItem<String>(
        value: 'Off',
        child: Text('Off', style: TextStyle(color: Colors.white)),
      ),
      for (final sub in controller.subtitles)
        PopupMenuItem<String>(
          value: sub.label,
          child: Text(sub.label, style: const TextStyle(color: Colors.white)),
        ),
    ],
  );
}
