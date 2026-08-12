import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:filefin_mobile/src/tv/tv_home_page.dart';
import 'package:filefin_mobile/src/tv/tv_library_page.dart';
import 'package:filefin_mobile/src/tv/tv_rail.dart';
import 'package:filefin_mobile/src/tv/tv_search_page.dart';
import 'package:flutter/material.dart';

/// The television's four destinations.
enum TvTab {
  /// The hero and the three rows.
  home,

  /// The tree on the left, its grid on the right.
  library,

  /// The on-screen keyboard and its results.
  search,

  /// Servers and playback settings.
  settings,
}

/// What a signed-in server looks like on a television: a rail, and one pane.
///
/// **The same build-on-first-selection rule as the phone shell, for the same
/// reason (NF1).** A cold start must issue one request, not four. Nothing here
/// is an `IndexedStack`: a selected tab stays built so returning to it does not
/// refetch, and a tab never opened has never asked the server anything.
class TvShell extends StatefulWidget {
  /// Browses [api] under [title].
  const TvShell({
    required this.api,
    required this.title,
    this.onPlay,
    this.onSignIn,
    this.onServers,
    this.onSettings,
    super.key,
  });

  /// The port every screen below this one uses.
  final LibraryApi api;

  /// The saved server's name — shown at the foot of the rail.
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

  /// Opens F11's server picker.
  final VoidCallback? onServers;

  /// Opens the playback settings sheet.
  final VoidCallback? onSettings;

  // Sign-out is deliberately NOT here. On a phone it is the second entry of
  // the header's sliders menu; a television has no such menu, so `app.dart`
  // hands it to the playback settings sheet instead — which is the one screen
  // the rail's Settings destination opens. A callback on this class would be
  // one nothing invokes, which is exactly what the coverage ratchet caught.

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  final _home = GlobalKey<TvHomePageState>();
  final _built = <TvTab>{TvTab.home};
  TvTab _tab = TvTab.home;

  void _select(TvTab tab) {
    // The settings destination is a sheet rather than a pane, so choosing it
    // opens the sheet and leaves the rail where it was. A fourth pane holding
    // one sheet would be a screen with nothing on it.
    if (tab == TvTab.settings) {
      widget.onSettings?.call();
      return;
    }
    setState(() {
      _tab = tab;
      _built.add(tab);
    });
  }

  /// The pane for [tab].
  ///
  /// **`settings` is absent from this switch and that is deliberate.** It is a
  /// sheet rather than a pane — `_select` opens it and leaves the rail where it
  /// was — so an arm for it would be a line no test could enter and no user
  /// could reach, which is what §1 asks not to be written. Naming the other
  /// three explicitly keeps the compile error a fifth destination should
  /// produce; `_paneFor` returning null is what the caller draws nothing for.
  Widget? _build(TvTab tab) => switch (tab) {
    TvTab.settings => null,
    TvTab.home => TvHomePage(
      key: _home,
      api: widget.api,
      onOpen: _openDetail,
      onSignIn: widget.onSignIn,
    ),
    TvTab.library => TvLibraryPage(
      api: widget.api,
      onOpen: _openDetail,
      onSignIn: widget.onSignIn,
    ),
    TvTab.search => TvSearchPage(
      api: widget.api,
      onOpen: _openDetail,
      onSignIn: widget.onSignIn,
    ),
  };

  /// The one detail route, and the one place the home rows are reloaded.
  ///
  /// The `push<bool>` result and `MediaDetailPage`'s explicit pop are a pair,
  /// exactly as they are on the phone: a write anywhere re-stamps `updated`,
  /// which orders all three home buckets (M6.0/E-3).
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
    body: Row(
      children: [
        TvRail(
          selected: _tab.index,
          serverName: widget.title,
          onServers: () => widget.onServers?.call(),
          onSelect: (index) => _select(TvTab.values[index]),
          destinations: const [
            TvDestination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: 'Home',
            ),
            TvDestination(
              icon: Icons.folder_copy_outlined,
              selectedIcon: Icons.folder_copy,
              label: 'Library',
            ),
            TvDestination(
              icon: Icons.search_outlined,
              selectedIcon: Icons.search,
              label: 'Search',
            ),
            TvDestination(
              icon: Icons.tune_outlined,
              selectedIcon: Icons.tune,
              label: 'Settings',
            ),
          ],
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final tab in TvTab.values)
                if (_built.contains(tab))
                  if (_build(tab) case final pane?)
                    Offstage(
                      key: ValueKey(tab),
                      offstage: tab != _tab,
                      child: TickerMode(enabled: tab == _tab, child: pane),
                    ),
            ],
          ),
        ),
      ],
    ),
  );
}
