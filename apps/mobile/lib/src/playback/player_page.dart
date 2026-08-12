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
/// Uses `MaterialVideoControlsTheme` from `media_kit_video` for transport
/// controls, fullscreen and orientation — the same prebuilt buttons the
/// library ships. The only custom pieces are the back button (top-left in
/// the controls bar) and the subtitle picker, both injected via
/// [PlaybackHost.buildSurface].
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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

  /// The title shown in the fullscreen top bar.
  ///
  /// For a single-file item: just the title. For a multi-file item:
  /// "Title — S01E02" when season/episode are present, "Title — filename"
  /// otherwise.
  String get _fullscreenTitle {
    final file = _controller.file;
    if (_controller.detail.files.length == 1) return widget.detail.title;
    if (file.season > 0 || file.episode > 0) {
      return '${widget.detail.title} — '
          '${file.season}x${file.episode.toString().padLeft(2, '0')}';
    }
    return '${widget.detail.title} — ${file.name}';
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _showSubtitlePicker() {
    final subtitles = _controller.subtitles;
    final current = _controller.subtitle;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Off'),
            selected: current == null,
            onTap: () {
              _controller.selectSubtitle(null);
              Navigator.pop(context);
            },
          ),
          if (subtitles.isEmpty)
            const ListTile(
              title: Text(
                'No subtitles available',
                style: TextStyle(color: Colors.white54),
              ),
              enabled: false,
            )
          else
            for (final sub in subtitles)
              ListTile(
                title: Text(sub.label),
                selected: sub.index == current?.index,
                onTap: () {
                  _controller.selectSubtitle(sub);
                  Navigator.pop(context);
                },
              ),
        ],
      ),
    );
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
        // MaterialVideoControlsTheme wraps the video surface and provides
        // play/pause, seek, skip, fullscreen, and our back/subtitle buttons.
        _controller.host.buildSurface(
          onBack: () => Navigator.of(context).maybePop(),
          // Always show the button — subtitles may not be loaded yet when
          // the fullscreen route pushes, and the captured widget tree never
          // sees the later state. The picker itself checks at tap time.
          onShowSubtitles: _showSubtitlePicker,
          onNext: _controller.hasNext ? () => _controller.next() : null,
          onPrevious: _controller.hasPrevious
              ? () => _controller.previous()
              : null,
          title: _fullscreenTitle,
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
