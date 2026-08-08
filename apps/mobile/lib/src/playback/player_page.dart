import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart'
    show humanSize;
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';

/// The player screen (F7, F8, F9, F13, NF6).
class PlayerPage extends StatefulWidget {
  /// Plays [detail]'s [initialFile], starting [startAt] seconds in.
  const PlayerPage({
    required this.api,
    required this.hostFactory,
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
    unawaited(_controller.start());
  }

  @override
  void dispose() {
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
  Widget build(BuildContext context) => PopScope(
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
      if (context.mounted) Navigator.of(context).pop();
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
    return Column(
      children: [
        if (widget.server.allowUnverifiedPlayback) const UnverifiedTlsBanner(),
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

/// The persistent banner D10 requires when unverified playback is on.
///
/// **A banner rather than a one-time dialog, and the difference is the point:**
/// what has been given up is ongoing, not a single act. It names exactly what
/// is unprotected instead of saying "insecure".
class UnverifiedTlsBanner extends StatelessWidget {
  /// Shows the standing warning.
  const UnverifiedTlsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // The scheme read once. Two `Theme.of(context)` calls in one build is a
    // small thing; the reason it is worth fixing is that collapsing the
    // `TextStyle(...)` onto one line also removes the only mutant in this file
    // that no assertion could kill — the argument-swap rule was matching a run
    // of closing parentheses and producing a whitespace-only rewrite.
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Text(
        'Unverified playback is on for this server. The player checks no '
        'certificate, so the session cookie may reach a server whose identity '
        'nobody verified.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

/// F13's confirmation, naming the real size.
class MeteredPrompt extends StatelessWidget {
  /// Asks about [bytes].
  const MeteredPrompt({
    required this.bytes,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  /// The file's actual size.
  final int bytes;

  /// Play anyway.
  final VoidCallback onConfirm;

  /// Go back.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.signal_cellular_alt, size: 48),
          const SizedBox(height: 16),
          Text(
            'This file is ${humanSize(bytes)} and you are on a metered '
            'connection.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onConfirm, child: const Text('Play anyway')),
          TextButton(onPressed: onCancel, child: const Text('Not now')),
        ],
      ),
    ),
  );
}

class _RefusalPanel extends StatelessWidget {
  const _RefusalPanel({required this.reason, required this.server});

  final RefuseReason reason;
  final SavedServer server;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, size: 48, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            switch (reason) {
              RefuseReason.offline =>
                'There is no connection, so there is nothing to stream over.',
              RefuseReason.wifiOnlyOnMetered =>
                'You are on a metered connection and "${server.name}" is set '
                    'to Wi-Fi only. Change it in playback settings to play '
                    'here.',
              RefuseReason.unverifiablePlaybackTls =>
                '"${server.name}" uses a certificate only this app trusts, and '
                    'the player cannot check it. Playing anyway would send the '
                    'session cookie to a server whose identity nobody '
                    'verified — turn on unverified playback for this server if '
                    'you accept that.',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message, this.onSignIn});

  final String message;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.errorContainer,
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
        if (onSignIn != null)
          TextButton(onPressed: onSignIn, child: const Text('Sign in')),
      ],
    ),
  );
}

/// Reporting stopped because the server rejected the report itself.
///
/// Non-blocking on purpose: playback carries on, and the only thing lost is the
/// resume pointer for this session.
class _ReportStoppedBanner extends StatelessWidget {
  const _ReportStoppedBanner();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.all(8),
    child: const Text(
      'Progress is no longer being saved: this item changed on the server. '
      'Go back and open it again.',
    ),
  );
}
