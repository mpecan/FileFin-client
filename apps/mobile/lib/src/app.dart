import 'package:filefin_mobile/src/browse/category_grid_page.dart';
import 'package:filefin_mobile/src/browse/category_tree_page.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/add_server_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
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
        onAdded: (server) => Navigator.of(context).pushReplacement<void, void>(
          _signInRoute(server, pops: 1),
        ),
      ),
    ),
  );

  /// The sign-in route, built once for both ways in.
  ///
  /// [pops] is how many routes to remove on success: one when sign-in replaced
  /// the add-server screen, one when it was pushed on its own. Written as one
  /// method rather than two call sites because two copies of this closure is
  /// two places for the client-swap to be got wrong — and closing the previous
  /// API is the half that leaks a socket when it is.
  MaterialPageRoute<void> _signInRoute(
    SavedServer server, {
    required int pops,
  }) => MaterialPageRoute(
    builder: (_) => SignInPage(
      server: server,
      onSignedIn: (signedIn, api) {
        setState(() {
          _api?.close();
          _api = api;
          _server = signedIn;
        });
        for (var i = 0; i < pops; i++) {
          Navigator.of(context).pop();
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final saved = FileFinScope.of(context).settings.read().servers;
    final server = _server;
    final api = _api;
    if (api != null && server != null) {
      return CategoryTreePage(
        api: api,
        title: server.name,
        // Sign-out on a SessionExpired is a state change here rather than a
        // route push: the tree, the grid and the detail page can all be the
        // screen that discovers the session is gone, and every one of them
        // must land on the same place.
        onSignIn: () => setState(() {
          _api?.close();
          _api = null;
          _server = null;
        }),
        onOpen: (category) => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CategoryGridPage(
              api: api,
              category: category,
              onOpen: (item) => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => MediaDetailPage(api: api, item: item),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return NoServerPage(
      savedCount: saved.length,
      onAddServer: _addServer,
      onSignIn: saved.isEmpty
          ? null
          : () => Navigator.of(
              context,
            ).push<void>(_signInRoute(saved.first, pops: 1)),
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
                  : 'FileFin keeps sessions in memory, so a server restart '
                        'signs everyone out. Sign in again to carry on.',
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
