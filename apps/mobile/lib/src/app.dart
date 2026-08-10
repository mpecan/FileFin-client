import 'dart:async';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/browse/library_shell.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/playback_settings_sheet.dart';
import 'package:filefin_mobile/src/playback/player_route.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/add_server_page.dart';
import 'package:filefin_mobile/src/servers/launch_pages.dart';
import 'package:filefin_mobile/src/servers/server_api.dart';
import 'package:filefin_mobile/src/servers/server_list_page.dart';
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

  /// True while F2's cold start is in flight.
  ///
  /// It is false unless something is actually happening, which is what keeps
  /// the first-launch screen an empty state rather than a spinner: with no
  /// saved server there is nothing to wait for and [_launch] returns without
  /// setting it.
  bool _resuming = false;

  /// Whether [_launch] has already run. `didChangeDependencies` fires again on
  /// every inherited-widget change, and a second launch would build a second
  /// client for the same server.
  bool _launched = false;

  /// Why the last launch did not reach a library, unless it merely expired.
  ///
  /// **Every reason used to land on the same silent "Signed out" screen**,
  /// including the one F15 exists to make loud: a `CertificatePinMismatch`
  /// read as an invitation to retype a password at a server whose identity had
  /// just failed. The words existed in `describeApiError`; nothing called them.
  FileFinApiException? _launchFailure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not `initState`: `FileFinScope.of` registers a dependency, which is only
    // legal from here down.
    if (_launched) return;
    _launched = true;
    _launch();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  /// F2's cold start: the saved session, restored without a password typed.
  ///
  /// Three outcomes, and the third is the one F2 exists for. No saved server
  /// lands on *"No server yet"*; a saved server whose secrets are gone lands on
  /// *"Signed out"*; and a saved server whose session the server has since
  /// forgotten is renewed silently by F3 from the stored password and lands in
  /// the library — see `LibraryApi.restore`.
  void _launch() {
    final target = FileFinScope.of(context).settings.read().selectedServer;
    if (target == null) return;
    _resuming = true;
    unawaited(_resume(target));
  }

  Future<void> _resume(SavedServer target) async {
    // `apiForServer`, not `apiFactory`: it resolves F15's accepted fingerprint
    // out of the secure store first. M7.5 wired the pin into every path that
    // builds a client EXCEPT this one, and this is the path F2 exists for — so
    // a self-signed server, F15's stated common case, failed every cold start
    // with `CertificateNotTrusted` and sent the user to type a password the
    // store already held.
    final api = await apiForServer(FileFinScope.of(context), target);
    try {
      await api.restore();
    } on FileFinApiException catch (error) {
      // `SessionExpired` ends on the sign-in screen with the server still
      // selected: `restore()` has deleted the dead cookie and kept the
      // password, so the NEXT launch is silent again. Every OTHER reason is a
      // different problem and now says which — see [_launchFailure].
      api.close();
      if (mounted) {
        setState(() {
          _resuming = false;
          _launchFailure = error is SessionExpired ? null : error;
        });
      }
      return;
    }
    if (!mounted) {
      api.close();
      return;
    }
    setState(() {
      _api = api;
      _server = target;
      _resuming = false;
      _launchFailure = null;
    });
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

  /// F11's picker, and the three things it can ask for.
  ///
  /// `onAdd` pops this route **before** starting the add-server flow, and that
  /// is not tidiness: [_signInRoute] pops exactly once on success, which is
  /// right only while sign-in sits directly on the launch screen. Pushing the
  /// flow on top of the picker would leave the picker showing over a freshly
  /// signed-in library.
  Future<void> _openServers() {
    final settings = FileFinScope.of(context).settings.read();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ServerListPage(
          selected: settings.selectedServerId,
          onSelect: (server) {
            Navigator.of(context).pop();
            unawaited(_switchTo(server));
          },
          onRemoved: _serverRemoved,
          onAdd: () {
            Navigator.of(context).pop();
            unawaited(_addServer());
          },
        ),
      ),
    );
  }

  /// F11's switch: one method, because closing the previous client is the half
  /// that leaks a socket when it is written twice.
  ///
  /// The selection is written **before** the restore rather than after it, so a
  /// server whose session has since died is still the one the next launch
  /// opens — the user asked for it, and landing back on the previous server
  /// tomorrow is not an answer to that.
  ///
  /// Clearing `_api` first is what makes the shell rebuild from nothing:
  /// `LibraryShell`'s tabs are `Offstage` rather than disposed, so a shell that
  /// survived the swap would keep the previous server's rows on screen under
  /// the new server's name.
  ///
  /// The write is caught, and this was the one `SettingsStore` call site of
  /// five that did not: `_switchTo` runs `unawaited(...)` with no
  /// `runZonedGuarded`, so a full disk closed the picker and said nothing.
  /// The switch still goes ahead; only the NEXT launch is affected.
  Future<void> _switchTo(SavedServer target) async {
    final settings = FileFinScope.of(context).settings;
    try {
      settings.write(settings.read().withSelected(target.id));
    } on FileSystemException catch (e) {
      _say(describeSettingsWriteFailure(e));
    }
    setState(() {
      _api?.close();
      _api = null;
      _server = target;
      _resuming = true;
      _launchFailure = null;
    });
    await _resume(target);
  }

  /// A server the picker has just forgotten.
  ///
  /// Only the one being *shown* costs a session. Closing the client whenever
  /// anything is removed would sign a user out of the server they are browsing
  /// because they tidied up a different one.
  void _serverRemoved(SavedServer removed) {
    if (_server?.id != removed.id) return;
    setState(() {
      _api?.close();
      _api = null;
      // Dropped, unlike in [_sessionExpired]: this server no longer exists, so
      // offering to sign in to it is offering a screen with nowhere to go.
      _server = null;
    });
  }

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
      _say(describeApiError(error).title);
    }
    if (mounted) _sessionExpired();
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
            _say(describeSettingsWriteFailure(e));
          }
        },
      ),
    );
  }

  /// Everything this route has to tell a user with no panel to put it in: a
  /// settings write that failed, and a sign-out the server did not answer.
  void _say(String message) =>
      (mounted ? ScaffoldMessenger.maybeOf(context) : null)?.showSnackBar(
        SnackBar(content: Text(message)),
      );

  @override
  Widget build(BuildContext context) {
    final settings = FileFinScope.of(context).settings.read();
    final saved = settings.servers;
    final server = _server;
    final api = _api;
    if (api != null && server != null) {
      // The five browsing screens and the routes between them moved into
      // `LibraryShell` at M6.7, because two of them — the `push<bool>` detail
      // route and the home reload it triggers — are a pair that only the
      // owner of the Home tab can wire.
      return LibraryShell(
        // The KEY is what makes a switch a new shell rather than the old one
        // wearing a new name. Its tabs are `Offstage`, not disposed, so without
        // it the Home tab keeps the previous server's rows and never asks the
        // new client for anything. Measured, not guessed: the assertion in
        // `app_servers_test.dart` fails without it.
        key: ValueKey(server.id.value),
        api: api,
        title: server.name,
        onServers: () => unawaited(_openServers()),
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
        onPlay: (detail, file, startAt) => pushPlayer(
          context,
          api: api,
          server: server,
          detail: detail,
          file: file,
          startAt: startAt,
          onSignIn: _sessionExpired,
        ),
      );
    }
    if (_resuming) return const ResumingPage();
    // The server signed out of, when there is one, rather than the selection:
    // with two saved servers the latter sent someone who signed out of the
    // second to the first.
    final target = server ?? settings.selectedServer;
    final failure = _launchFailure;
    return NoServerPage(
      savedCount: saved.length,
      problem: failure == null ? null : describeApiError(failure),
      onAddServer: _addServer,
      onSignIn: target == null || failure is CertificatePinMismatch
          ? null
          : () => Navigator.of(context).push<void>(_signInRoute(target)),
      // Offered from here too, and gated on there being something to pick or
      // forget: with two saved servers and none signed in, [onSignIn] reaches
      // exactly one of them and this is the only route to the other.
      onServers: saved.isEmpty ? null : () => unawaited(_openServers()),
    );
  }
}
