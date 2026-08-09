import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/category_grid_page.dart';
import 'package:filefin_mobile/src/browse/category_tree_page.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/browse/search_page.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:flutter/material.dart';

/// The three top-level destinations of a signed-in server.
///
/// An enum rather than an `int`, so [LibraryShell]'s builder switches with no
/// default arm and a fourth destination is a compile error rather than a blank
/// tab.
enum LibraryTab {
  /// F6's three rows.
  home,

  /// F4's category tree.
  library,

  /// F5's search.
  search,
}

/// What a signed-in server looks like: Home, Library and Search, and the one
/// route that opens an item from any of them.
///
/// **Tabs are built on first selection, never before, and NF1 is why.** A cold
/// start must issue one request, not three: `IndexedStack` and a `TabBarView`
/// both build every child immediately, so choosing either would have made a
/// launch fetch the home rows, the category list and an empty search at once —
/// on a phone, over someone's cellular connection, for two screens they may
/// never open. A tab that has been selected stays built, so switching back does
/// not refetch.
///
/// **One `_openDetail` for all three tabs.** The detail route pops `true` when
/// it wrote watch state, and that is the only thing that reloads the home rows.
/// The rows cannot be predicted — every write re-stamps `updated` and every
/// bucket is ordered by it (M6.0/E-3) — so "something changed" is the most a
/// screen can honestly say, and the refetch is the answer.
///
/// **The rejected alternative is worth naming**: a `WatchStateBus` shared by
/// the three tabs, so a write anywhere updated everything. That is precisely
/// the "a second state mechanism appears" condition `docs/architecture.md`
/// gives for retiring D-Q1, and it is not built for one method call on one key.
class LibraryShell extends StatefulWidget {
  /// Browses [api] under [title].
  const LibraryShell({
    required this.api,
    required this.title,
    this.onPlay,
    this.onSignIn,
    this.onSettings,
    this.onSignOut,
    super.key,
  });

  /// The port every screen below this one uses.
  final LibraryApi api;

  /// The saved server's name — the app-bar title of the two library tabs.
  final String title;

  /// Opens the player. Null in a test that is not about playback.
  final Future<PlaybackOutcome?> Function(
    MediaDetail detail,
    FileIndex file,
    Duration startAt,
  )?
  onPlay;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  /// Opens the playback settings sheet.
  final VoidCallback? onSettings;

  /// Ends the session and forgets this account (F2, §9).
  ///
  /// Distinct from [onSignIn], which is what a `SessionExpired` reaches: that
  /// one is the server having already forgotten, and the stored password is
  /// what F3 renews from, so it must NOT be cleared. This is the user asking
  /// to be forgotten, and it clears everything.
  final VoidCallback? onSignOut;

  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell> {
  /// The home tab's state, so a write anywhere can reload its rows.
  final _home = GlobalKey<HomePageState>();

  /// Which tabs have been selected so far.
  ///
  /// **A set of tabs, never a map of widgets, and the difference was a
  /// data-loss bug.** Caching the built `Widget` froze every argument it was
  /// built from: `widget.onSettings` is a closure `app.dart` rebuilds around
  /// the current `SavedServer` on every build, so a Home tab holding the
  /// instance from `initState` kept handing the settings sheet the server as it
  /// was at sign-in. Wi-Fi only and D10's allowance both reverted to their
  /// sign-in values on the second visit, and the next toggle wrote the stale
  /// value back (M6.R/P1.1). `api`, `title` and `onSignIn` were frozen by the
  /// same mechanism and happened to be stable.
  ///
  /// Rebuilding each selected tab on every build is what Flutter expects
  /// anyway: the `Offstage`'s `ValueKey(tab)` is what carries each tab's
  /// element — and so its state and its scroll position — across a rebuild that
  /// inserts a tab ahead of it in the stack.
  final _built = <LibraryTab>{LibraryTab.home};

  LibraryTab _tab = LibraryTab.home;

  void _select(LibraryTab tab) => setState(() {
    _tab = tab;
    _built.add(tab);
  });

  Widget _build(LibraryTab tab) => switch (tab) {
    LibraryTab.home => HomePage(
      key: _home,
      api: widget.api,
      title: widget.title,
      onOpen: _openDetail,
      onSignIn: widget.onSignIn,
      onSettings: widget.onSettings,
      onSignOut: widget.onSignOut,
    ),
    LibraryTab.library => CategoryTreePage(
      api: widget.api,
      title: widget.title,
      onOpen: _openCategory,
      onSignIn: widget.onSignIn,
      onSettings: widget.onSettings,
      onSignOut: widget.onSignOut,
    ),
    LibraryTab.search => SearchPage(
      api: widget.api,
      onOpen: _openDetail,
      onSignIn: widget.onSignIn,
    ),
  };

  void _openCategory(Category category) => unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CategoryGridPage(
          api: widget.api,
          category: category,
          onSignIn: widget.onSignIn,
          onOpen: _openDetail,
        ),
      ),
    ),
  );

  /// The one detail route, and the one place the home rows are reloaded.
  ///
  /// `push<bool>` and `MediaDetailPage`'s explicit pop are a pair: the ordinary
  /// back affordances call `Navigator.maybePop(context)` with no result, so
  /// without that page's `PopScope` this would receive null on every normal
  /// exit — which is exactly when a write has happened.
  Future<void> _openDetail(MediaSummary item) async {
    final wrote = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MediaDetailPage(
          api: widget.api,
          item: item,
          onSignIn: widget.onSignIn,
          onPlay: widget.onPlay,
        ),
      ),
    );
    if (wrote ?? false) await _home.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // A `Stack` of the tabs built so far rather than an `IndexedStack`, which
    // would build all three. `Offstage` keeps a selected-then-left tab's state
    // and its scroll position, and finders skip it, so "the Library tab's app
    // bar" cannot be found while Home is showing.
    body: Stack(
      // Tight constraints, so each tab's own `Scaffold` fills the shell. A
      // loose `Stack` would let one shrink-wrap its app bar.
      fit: StackFit.expand,
      children: [
        for (final tab in LibraryTab.values)
          if (_built.contains(tab))
            Offstage(
              key: ValueKey(tab),
              offstage: tab != _tab,
              child: TickerMode(enabled: tab == _tab, child: _build(tab)),
            ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab.index,
      onDestinationSelected: (index) => _select(LibraryTab.values[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          selectedIcon: Icon(Icons.video_library),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: 'Search',
        ),
      ],
    ),
  );
}
