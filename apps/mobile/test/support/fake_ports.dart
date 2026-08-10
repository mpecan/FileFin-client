import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';

import 'fake_now_playing.dart';
import 'fake_playback_host.dart';

/// A `NetworkStatus` that answers whatever a test set, with no plugin.
final class FakeNetworkStatus extends NetworkStatus {
  /// Answers [answer] until a test changes it.
  FakeNetworkStatus([this.answer = NetworkType.wifi]);

  /// What the next sample returns.
  NetworkType answer;

  /// How many times it was sampled — F13 says exactly once, before playing.
  int samples = 0;

  @override
  Future<NetworkType> current() async {
    samples++;
    return answer;
  }
}

/// A playback host factory for a widget test: never libmpv, never a `Video`.
PlaybackHost Function() fakeHostFactory() => FakePlaybackHost.new;

/// A media-session factory for a widget test: never `AudioService.init`.
///
/// Answers [session] when a test wants to read what F14 published, and a
/// throwaway otherwise.
Future<NowPlayingHost> Function() fakeNowPlayingFactory([
  FakeNowPlaying? session,
]) =>
    () async => session ?? FakeNowPlaying();
