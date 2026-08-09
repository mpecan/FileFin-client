import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/library_actions.dart';
import 'package:filefin_mobile/src/browse/media_row.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';

/// F6: the three rows `GET /api/home` returns, in the order it returns them.
///
/// **Refetched after a write, never predicted, and that is measured rather than
/// cautious.** The rows come from the `user_state` mirror rather than from
/// `meta.json` (`media.go:227`), the mirror upsert is best-effort, and every
/// bucket is `ORDER BY us.updated DESC` where `updated` is re-stamped by
/// *every* write — so setting a rating re-orders the *Continue watching* row
/// (M6.0/E-3). None of that is derivable from what a client holds, and a
/// prediction that was *more* right than the server would still look like a
/// bug. [HomePageState.reload] is the whole mechanism, and the detail
/// route's `bool` result is what triggers it.
///
/// **An item legitimately appears in more than one row.** The captured
/// `home_populated.json` has the film in `continue` *and* in `favorites`,
/// because the buckets are independent predicates over one `user_state` row
/// rather than a partition. Nothing here de-duplicates.
class HomePage extends StatefulWidget {
  /// Shows [api]'s home rows under [title]; [onOpen] opens an item.
  const HomePage({
    required this.api,
    required this.title,
    required this.onOpen,
    this.onSignIn,
    this.onServers,
    this.onSettings,
    this.onSignOut,
    super.key,
  });

  /// Where the rows and the posters come from.
  final LibraryApi api;

  /// The app-bar title — the saved server's name.
  final String title;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  /// Opens F11's server picker.
  final VoidCallback? onServers;

  /// Opens the playback settings sheet.
  ///
  /// Offered here **as well as** on the category tree, deliberately: this is
  /// the tab a signed-in launch lands on, and a setting reachable only from a
  /// tab you have to know to visit is a setting nobody finds.
  final VoidCallback? onSettings;

  /// Ends the session and forgets this account (F2, §9).
  final VoidCallback? onSignOut;

  @override
  State<HomePage> createState() => HomePageState();
}

/// The state, public for one reason: [reload].
///
/// The shell holds a `GlobalKey<HomePageState>` and calls it when a detail
/// route pops `true`. The rejected alternative — a shared `WatchStateBus`
/// across the three tabs — is exactly what would trip D-Q1's retirement
/// condition in `docs/architecture.md`, and it is deliberately not built for a
/// single method call.
class HomePageState extends State<HomePage> {
  late final AsyncController<HomeRows> _controller = AsyncController<HomeRows>(
    (token) => widget.api.home(cancelToken: token),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Refetches all three rows.
  ///
  /// Called when something wrote watch state, from this tab or from the
  /// category grid. It goes through [AsyncController.load], so an in-flight
  /// fetch is cancelled and cannot land after this one.
  Future<void> reload() => _controller.load();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: libraryAppBarActions(
        onServers: widget.onServers,
        onSettings: widget.onSettings,
        onSignOut: widget.onSignOut,
      ),
    ),
    body: AsyncView<HomeRows>(
      controller: _controller,
      onSignIn: widget.onSignIn,
      builder: (context, rows) {
        if (rows.continueRow.isEmpty &&
            rows.favorites.isEmpty &&
            rows.completed.isEmpty) {
          return const _NothingYet();
        }
        return ListView(
          children: [
            MediaRow(
              api: widget.api,
              label: 'Continue watching',
              items: rows.continueRow,
              onOpen: widget.onOpen,
            ),
            MediaRow(
              api: widget.api,
              label: 'Favourites',
              items: rows.favorites,
              onOpen: widget.onOpen,
            ),
            // "Watched", not "Completed": the wire key is `completed` and the
            // predicate is `us.watched = 1`, so the row is what the user has
            // marked watched and nothing to do with finishing a series.
            MediaRow(
              api: widget.api,
              label: 'Watched',
              items: rows.completed,
              onOpen: widget.onOpen,
            ),
          ],
        );
      },
    ),
  );
}

/// Three empty rows, which is what a fresh account really looks like.
///
/// An empty state rather than three empty headings: every bucket is keyed on
/// per-user state, so a server with a full library still answers `{[], [], []}`
/// to someone who has not watched, favourited or marked anything.
class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Nothing here yet. What you play, favourite or mark watched shows up '
        'on this screen. Browse the library to get started.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
