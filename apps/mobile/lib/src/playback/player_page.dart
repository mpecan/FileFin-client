import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/file_list.dart'
    show fileLabel, humanSize;
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'player_panels.dart';

/// The mono line under the title on the overlay's top bar.
///
/// Which file, what container, and **how it is being served** — the last of
/// which is the one thing a user cannot see anywhere else and the one that
/// explains a slow start. `transcode` is the server's own verdict
/// (`internal/server/playback.go:78`), not a guess from the extension.
///
/// Public only so a test can reach it; nothing outside this library calls it
/// (§5, `public_member_no_consumer`).
@visibleForTesting
String playerFacts(PlayerController controller) {
  final file = controller.file;
  return [
    if (controller.detail.files.length > 1) fileLabel(file),
    if (file.ext.isNotEmpty) file.ext.replaceFirst('.', ''),
    if (file.transcode) 'transcode' else 'direct play',
  ].join(' · ');
}

/// The player screen (F7, F8, F9, F13, NF6).
///
/// The video surface comes from [PlaybackHost.buildSurface] and carries no
/// controls at all; [PlayerControls] is stacked over it and is the whole of
/// F7's transport, both on a phone and on a television.
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
    required this.metrics,
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

  /// Phone or television sizing for the overlay.
  final PlayerControlsMetrics metrics;

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
    // A television is already landscape and has no sensor to disagree with;
    // asking Android TV to rotate is a no-op that logs.
    if (widget.metrics == PlayerControlsMetrics.phone) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => unawaited(_controller.handleLifecycle(state)),
    );
    _controller.addListener(_onChange);
    unawaited(_bindSession());
    unawaited(_controller.start());
  }

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

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
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
        // The surface is the video and nothing else; every control is the
        // overlay stacked on it. Until the redesign the two swapped places —
        // the engine built the shipped controls and this page built none — so
        // what widget tests drove was never what a user saw.
        //
        // **`ExcludeFocus`, and it is not optional on a television.**
        // `media_kit_video`'s `Video` is focusable, and a focusable thing
        // filling the screen under the overlay takes focus and keeps it: the
        // remote then reaches no control at all, which is the whole player
        // unusable rather than one button missing. `1b48603` had this around
        // the same texture inside the overlay `RealMpvPlayer.buildSurface`
        // used to build, and deleting that class to make `PlayerControls` the
        // one set of controls took it with it. Found on a Google TV Streamer,
        // then pinned two ways in `player_page_test.dart` — structurally, and
        // by a D-pad walk that reached `VIDEO` and nothing else.
        ExcludeFocus(child: _controller.host.buildSurface()),
        PlayerControls(
          controller: _controller,
          title: widget.detail.title,
          facts: playerFacts(_controller),
          metrics: widget.metrics,
          onBack: () => Navigator.of(context).maybePop(),
          // The pickers are always offered — tracks may not be loaded yet when
          // this route pushes, and the captured widget tree never sees the
          // later state. Each picker checks what it has at tap time.
          onShowSubtitles: () => showSubtitlePicker(context, _controller),
          onShowAudio: () => showAudioPicker(context, _controller),
        ),
        // Banners overlaid on top.
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
      ],
    );
  }
}
