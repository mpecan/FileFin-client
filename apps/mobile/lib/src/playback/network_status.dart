import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:meta/meta.dart';

/// What kind of connection the device is on.
///
/// A port for the same reason `LibraryApi` is one: `Connectivity` is a plugin
/// behind a method channel, and a widget test that wants the metered prompt
/// should not have to stand one up. The seam is proven rather than assumed —
/// `ConnectivityPlatform.instance` substitutes headlessly (measured at
/// ), which is what keeps [ConnectivityNetworkStatus] itself covered.
///
/// `one_member_abstracts` wants a top-level function instead, and it is wrong
/// here for the reason it would be wrong about `SecretStore`: a top-level
/// function cannot be substituted, and `base` is what makes a second method a
/// compile error in every implementor the day one arrives.
// The lint above is answered in this class's doc comment.
// ignore: one_member_abstracts
abstract base class NetworkStatus {
  /// Allows implementations to be `const`.
  const NetworkStatus();

  /// Samples the connection **now**.
  ///
  /// The rule says "before playing", so `PlayerController` calls this once at
  /// start and never subscribes. A mid-playback switch from Wi-Fi to cellular
  /// is out of scope and recorded as debt rather than silently handled.
  Future<NetworkType> current();
}

/// Maps `connectivity_plus`'s transports onto [NetworkType], conservatively.
///
/// **The plugin reports a transport, not a cost**, and none of its eight
/// values says "metered". So `wifi` and `ethernet` are the only two we can
/// *show* to be unmetered and everything else is treated as metered — `vpn`
/// included, because a VPN reports as `vpn` over whatever it tunnels through.
/// `none` entries are dropped first; a list containing `wifi` prefers `wifi`,
/// because the OS reports every active transport at once.
///
/// The residual is the exact case the guard exists for: **a tethered hotspot
/// reports as `wifi`**, so the guard does not fire.
/// `docs/verification-backlog.md` row 20 has the device experiment.
@visibleForTesting
NetworkType networkTypeOf(List<ConnectivityResult> results) {
  final usable = results.where((r) => r != ConnectivityResult.none).toList();
  if (usable.isEmpty) return NetworkType.none;
  final unmetered = usable.any(
    (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
  );
  return unmetered ? NetworkType.wifi : NetworkType.metered;
}

/// The real thing: one `checkConnectivity()` through the platform channel.
final class ConnectivityNetworkStatus extends NetworkStatus {
  /// Samples through [connectivity], or the plugin's own singleton.
  ConnectivityNetworkStatus({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<NetworkType> current() async =>
      networkTypeOf(await _connectivity.checkConnectivity());
}
