import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';

/// Pushes the player, wired from the one scope the whole app is built on.
///
/// **Built here rather than inside the detail page** so the two ports playback
/// needs — the connection sample and the engine factory — come from that scope,
/// and a widget test substitutes both by building it.
///
/// **It returns the route's result**, which carries the local reflection back
/// to the detail screen: without it `MediaDetailPage` showed a resume offset
/// from before playback started.
///
/// A free function rather than a method on `_HomeRouteState`: it touches no
/// state, needing only the scope above [context] and its arguments.
Future<PlaybackOutcome?> pushPlayer(
  BuildContext context, {
  required LibraryApi api,
  required SavedServer server,
  required MediaDetail detail,
  required FileIndex file,
  required Duration startAt,
  required PlayerControlsMetrics metrics,
  required VoidCallback onSignIn,
}) {
  final deps = FileFinScope.of(context);
  return Navigator.of(context).push<PlaybackOutcome>(
    MaterialPageRoute(
      builder: (_) => PlayerPage(
        api: api,
        hostFactory: deps.playbackHostFactory,
        nowPlayingFactory: deps.nowPlayingFactory,
        network: deps.network,
        detail: detail,
        server: server,
        prefs: deps.settings.read().playback,
        initialFile: file,
        startAt: startAt,
        metrics: metrics,
        onSignIn: onSignIn,
      ),
    ),
  );
}
