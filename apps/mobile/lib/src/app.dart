import 'dart:async';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/library_shell.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/playback_settings_sheet.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/add_server_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/servers/sign_in_page.dart';
import 'package:flutter/material.dart';

/// The application shell: one `MaterialApp`, one theme, one home.
class FileFinApp extends StatelessWidget {
  /// Builds the shell.
  const FileFinApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FileFin',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
      useMaterial3: true,
    ),
    home: const HomeRoute(),
  );
}

/// Picks the first screen from what is actually saved.
///
/// **Navigator pushes rather than a named-route table**, and that is a
/// decision rather than an omission: every screen here needs a typed argument
/// (a `SavedServer`, then a `LibraryApi`), and a named route hands over
/// `Object?`. The routing surface is three pushes; a router package would be a
/// dependency paying rent of "three pushes" (§4).
class HomeRoute extends StatefulWidget {
  /// Chooses between the empty state and the saved-server flow.
  const HomeRoute({super.key});

  @override
  State<HomeRoute> createState() => _HomeRouteState();
}

class _HomeRouteState extends State<HomeRoute> {
  LibraryApi? _api;
  SavedServer? _server;

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _addServer() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => AddServerPage(
        // `pushReplacement`, so Back from sign-in returns to the launch screen
        // rather than to an address the user has already answered for.
        onAdded: (server) => Navigator.of(
          context,
        ).pushReplacement<void, void>(_signInRoute(server)),
      ),
    ),
  );

  /// The sign-in route, built once for both ways in.
  ///
  /// One method rather than two call sites because two copies of this closure
  /// is two places for the client-swap to be got wrong — and closing the
  /// previous API is the half that leaks a socket when it is.
  ///
  /// Exactly one `pop` on success, from both ways in: sign-in either replaced
  /// the add-server screen or was pushed straight onto the launch screen, and
  /// in both cases it is one route above the root.
  MaterialPageRoute<void> _signInRoute(SavedServer server) => MaterialPageRoute(
    builder: (_) => SignInPage(
      server: server,
      onSignedIn: (signedIn, api) {
        setState(() {
          _api?.close();
          _api = api;
          _server = signedIn;
        });
        Navigator.of(context).pop();
      },
    ),
  );

  /// What a `SessionExpired` on ANY browsing screen does.
  ///
  /// Two halves, and both are needed. `popUntil` is the half the tree does not
  /// need and the grid and the detail page do: this is a state change on this
  /// route, so without it the user is returned to a signed-out shell sitting
  /// under two pushed routes they must dismiss by hand. Clearing the API is
  /// what makes [build] draw the signed-out screen at all.
  ///
  /// [_server] is deliberately KEPT. It is what the sign-in button then offers,
  /// and dropping it sent someone who signed out of their second server to
  /// their first one — silently, with no picker anywhere to correct it.
  ///
  /// **It deliberately does NOT call `logout()`, and that is the whole
  /// distinction from [_signOut].** A `SessionExpired` means the server has
  /// already forgotten this session; the stored *password* is what F3 renews
  /// from and what F2's silent cold start needs, so clearing it here would
  /// turn every server restart into a password prompt — the case F2 exists to
  /// remove.
  void _sessionExpired() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _api?.close();
      _api = null;
    });
  }

  /// The user asking to be forgotten (F2, §9).
  ///
  /// `logout()` first, then the local drop, and the order is load-bearing:
  /// closing the client releases the sockets the request would travel on.
  ///
  /// A server that does not answer still signs the user out here.
  /// `SessionManager.logout`'s `finally` has already cleared the jar and both
  /// secrets by the time it throws, so treating the throw as "still signed in"
  /// would leave the app claiming a session neither side holds — and someone
  /// whose server is down could never leave it. The failure is said out loud
  /// rather than swallowed.
  ///
  /// It takes the API rather than reading [_api] so there is no
  /// "what if there isn't one" branch: the affordance only exists on a
  /// signed-in shell, and a guard for a case the UI cannot produce is a dead
  /// branch (§5) that nothing could ever cover.
  Future<void> _signOut(LibraryApi api) async {
    try {
      await api.logout();
    } on FileFinApiException catch (error) {
      _messenger?.showSnackBar(
        SnackBar(content: Text(describeApiError(error).title)),
      );
    }
    if (mounted) _sessionExpired();
  }

  /// The player route.
  ///
  /// Built here rather than inside the detail page so the two ports playback
  /// needs — the connection sample and the engine factory — come from the one
  /// scope the whole app is built on, and a widget test substitutes both by
  /// building that scope.
  ///
  /// **It returns the route's result**, which is what carries F9's local
  /// reflection back to the detail screen: without it `MediaDetailPage` showed
  /// a resume offset from before playback started and M1's divergence latch
  /// discharged nothing (M4.R/P3).
  Future<PlaybackOutcome?> _play(
    LibraryApi api,
    SavedServer server,
    MediaDetail detail,
    FileIndex file,
    Duration startAt,
  ) {
    final deps = FileFinScope.of(context);
    return Navigator.of(context).push<PlaybackOutcome>(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          api: api,
          hostFactory: deps.playbackHostFactory,
          network: deps.network,
          detail: detail,
          server: server,
          prefs: deps.settings.read().playback,
          initialFile: file,
          startAt: startAt,
          onSignIn: _sessionExpired,
        ),
      ),
    );
  }

  /// The playback settings sheet, and the write it produces.
  ///
  /// The write is caught here rather than in the sheet because this is the
  /// screen with somewhere to say so: `SettingsStore.write` throws on a full
  /// disk or a revoked permission, and a setting that silently did not stick is
  /// worse than one that refused.
  void _playbackSettings(SavedServer server) {
    final settings = FileFinScope.of(context).settings;
    unawaited(
      showPlaybackSettings(
        context,
        server: server,
        prefs: settings.read().playback,
        onChanged: (changed, prefs) {
          setState(() => _server = changed);
          try {
            settings.write(settings.read().upsert(changed).withPlayback(prefs));
          } on FileSystemException catch (e) {
            _messenger?.showSnackBar(
              SnackBar(content: Text(describeSettingsWriteFailure(e))),
            );
          }
        },
      ),
    );
  }

  ScaffoldMessengerState? get _messenger =>
      mounted ? ScaffoldMessenger.maybeOf(context) : null;

  @override
  Widget build(BuildContext context) {
    final saved = FileFinScope.of(context).settings.read().servers;
    final server = _server;
    final api = _api;
    if (api != null && server != null) {
      // The five browsing screens and the routes between them moved into
      // `LibraryShell` at M6.7, because two of them — the `push<bool>` detail
      // route and the home reload it triggers — are a pair that only the
      // owner of the Home tab can wire.
      return LibraryShell(
        api: api,
        title: server.name,
        onSettings: () => _playbackSettings(server),
        // Sign-out on a SessionExpired is a state change here rather than a
        // route push: home, the tree, the grid, search and the detail page can
        // all be the screen that discovers the session is gone, and every one
        // of them must land on the same place. All of them therefore get
        // `_signOut` — the grid and the detail page shipped M3 without it,
        // which left the two screens a user actually lives in showing "Please
        // sign in again" with no button and no retry.
        onSignIn: _sessionExpired,
        onSignOut: () => unawaited(_signOut(api)),
        onPlay: (detail, file, startAt) =>
            _play(api, server, detail, file, startAt),
      );
    }
    // The server signed out of, when there is one, rather than `saved.first`:
    // with two saved servers the latter sent someone who signed out of the
    // second to the first, and there is no picker to correct it with.
    final target = server ?? (saved.isEmpty ? null : saved.first);
    return NoServerPage(
      savedCount: saved.length,
      onAddServer: _addServer,
      onSignIn: target == null
          ? null
          : () => Navigator.of(context).push<void>(_signInRoute(target)),
    );
  }
}

/// What a launch shows before a server is signed in to.
///
/// An empty state rather than a spinner, and the distinction is the point:
/// "nothing here" and "still loading" look identical if you show a spinner for
/// both, and a first launch has nothing to wait for.
class NoServerPage extends StatelessWidget {
  /// Shows the empty state, offering sign-in when [savedCount] is non-zero.
  const NoServerPage({
    required this.onAddServer,
    this.savedCount = 0,
    this.onSignIn,
    super.key,
  });

  /// How many servers `settings.json` holds.
  final int savedCount;

  /// Starts F1's add-a-server flow.
  final VoidCallback onAddServer;

  /// Signs in to the saved server, when there is one.
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FileFin')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              savedCount == 0 ? 'No server yet' : 'Signed out',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              savedCount == 0
                  ? 'Add the address of your FileFin server to browse its '
                        'library.'
                  // NOT "a server restart signs everyone out": F3 renews and
                  // replays that transparently and the user never sees this
                  // screen for it. What lands here is having no password to
                  // renew with — which at present is every fresh launch.
                  : 'Your password is kept only while this app is running, so '
                        'a fresh launch starts signed out. Sign in again to '
                        'carry on.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (onSignIn != null)
              FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
            TextButton(
              onPressed: onAddServer,
              child: const Text('Add a server'),
            ),
          ],
        ),
      ),
    ),
  );
}
