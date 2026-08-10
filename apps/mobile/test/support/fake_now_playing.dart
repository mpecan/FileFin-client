import 'dart:async';

import 'package:filefin_mobile/src/playback/now_playing.dart';

/// A `NowPlayingHost` a test can read and push into.
///
/// Argument-aware for the reason `FakePlaybackHost` is: a fake that counted
/// calls could not tell "S1E1" from "S1E2", and naming the wrong episode on a
/// lock screen is exactly F14's likely defect.
final class FakeNowPlaying implements NowPlayingHost {
  final _commands = StreamController<TransportCommand>.broadcast();

  /// Every metadata published, in order.
  final List<NowPlayingItem> published = [];

  /// Every transport state published, in order.
  final List<NowPlayingTransport> updates = [];

  /// How many times the session was torn down.
  int cleared = 0;

  @override
  Stream<TransportCommand> get commands => _commands.stream;

  @override
  Future<void> publish(NowPlayingItem metadata) async =>
      published.add(metadata);

  @override
  Future<void> update(NowPlayingTransport playback) async =>
      updates.add(playback);

  @override
  Future<void> clear() async => cleared++;

  /// Pretends the OS pressed a transport button.
  void send(TransportCommand command) => _commands.add(command);

  /// Closes the command stream.
  Future<void> dispose() => _commands.close();
}
