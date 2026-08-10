import 'dart:async';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/file_list.dart' show humanSize;
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';

part 'player_panels.dart';

/// The player screen (F7, F8, F9, F13, NF6).
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

  @override
  void initState() {
    super.initState();
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
  Future<void> _bindSession() async {
    final session = await widget.nowPlayingFactory();
    if (_gone) {
      await session.clear();
      return;
    }
    _binder = NowPlayingBinder(session: session, controller: _controller);
  }

  @override
  void dispose() {
    _gone = true;
    unawaited(_binder?.dispose());
    _lifecycle?.dispose();
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => PopScope<PlaybackOutcome>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      // The final `stop` is AWAITED here and fired again unawaited from
      // dispose as a backstop, bounded so a dead server cannot trap the user
      // on the player screen.
      await _controller.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      // The outcome is READ AFTER that final report, which is the whole reason
      // it is awaited: the last `stop` is what moves the pointer to where the
      // user actually stopped, and a value taken before it would hand the
      // detail screen a state one report out of date (F9).
      if (context.mounted) Navigator.of(context).pop(_controller.outcome);
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.detail.title)),
      body: SafeArea(child: _body()),
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
    // F12's whole surface, and a PANEL rather than the banner below because
    // there is nothing behind it: the pre-flight refused before the engine was
    // ever opened, so the video surface would be a black rectangle and the
    // controls would drive a player holding no file. The "before" this
    // replaces is mpv's own `Failed to open <url>.` over exactly that black
    // rectangle (measured verbatim, M5.0/E-I).
    if (_controller.unplayable != null) {
      return _UnplayablePanel(server: widget.server);
    }
    return Column(
      children: [
        // Keyed on the TRANSPORT and not only on the setting. With the flag on
        // and an OS-trusted certificate, `PlayerController` passes
        // `verifyTls: true` and mpv really does verify — so the banner's
        // "the player checks no certificate" was simply false, on every server
        // whose owner had ever turned the flag on (M4.R/P5). D10's guarantee
        // never depended on it, because the banner cannot under-fire: this is
        // the cry-wolf half.
        if (widget.api.playbackTransport() == PlaybackTransport.pinnedTls &&
            widget.server.allowUnverifiedPlayback)
          const UnverifiedTlsBanner(),
        if (_controller.failure != null)
          _FailureBanner(
            message: _controller.failure!,
            onSignIn: _controller.needsSignIn ? widget.onSignIn : null,
          ),
        if (_controller.reportStop == ReportStop.rejected)
          const _ReportStoppedBanner(),
        Expanded(child: Center(child: _controller.host.buildSurface())),
        PlayerControls(controller: _controller),
      ],
    );
  }
}
