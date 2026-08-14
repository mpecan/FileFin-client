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
import 'package:filefin_mobile/src/shell/nav_bar.dart';
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
/// **Tabs are built on first selection, never before, and NF1 is why**: a cold
/// start must issue one request, not three, where `IndexedStack` and
/// `TabBarView` build every child at once. A selected tab stays built.
///
/// **One `_openDetail` for all three tabs**, popping `true` when it wrote watch
/// state — the only thing that reloads the home rows (`docs/field-notes.md`).
/// The rejected alternative is worth naming: a `WatchStateBus` across the three
/// tabs, exactly the "second state mechanism" D9 names as its retirement
/// condition.
class LibraryShell extends StatefulWidget {
  /// Browses [api] under [title].
  const LibraryShell({
    required this.api,
    required this.title,
    this.onPlay,
    this.onSignIn,
    this.onServers,
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

  /// Opens F11's server picker: switch to another saved server, or forget
  /// one. The switch itself is `HomeRoute`'s, because closing the previous
  /// client is.
  final VoidCallback? onServers;

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
  /// built from, including the `onSettings` closure `app.dart` rebuilds around
  /// the current `SavedServer` — so Wi-Fi only and D10's allowance reverted to
  /// their sign-in values on a second visit and the next toggle wrote the stale
  /// value back (M6.R/P1.1).
  ///
  /// Rebuilding each selected tab is what Flutter expects anyway: the
  /// `Offstage`'s `ValueKey(tab)` carries each tab's element, and so its state
  /// and scroll position, across a rebuild.
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
      onSearch: () => _select(LibraryTab.search),
      onServers: widget.onServers,
      onSettings: widget.onSettings,
      onSignOut: widget.onSignOut,
    ),
    LibraryTab.library => CategoryTreePage(
      api: widget.api,
      title: widget.title,
      onOpen: _openCategory,
      onSignIn: widget.onSignIn,
      onSearch: () => _select(LibraryTab.search),
      onServers: widget.onServers,
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
    bottomNavigationBar: ShellNavBar(
      selected: _tab.index,
      onSelect: (index) => _select(LibraryTab.values[index]),
      destinations: const [
        ShellDestination(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Home',
        ),
        ShellDestination(
          icon: Icons.folder_copy_outlined,
          selectedIcon: Icons.folder_copy,
          label: 'Library',
        ),
        ShellDestination(
          icon: Icons.search_outlined,
          selectedIcon: Icons.search,
          label: 'Search',
        ),
      ],
    ),
  );
}
