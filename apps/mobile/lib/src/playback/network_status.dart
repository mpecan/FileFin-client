import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:filefin_core/filefin_core.dart';

/// What kind of connection the device is on (F13).
///
/// A port for the same reason `LibraryApi` is one: `Connectivity` is a plugin
/// behind a method channel, and a widget test that wants the metered prompt
/// should not have to stand one up. The seam is proven rather than assumed —
/// `ConnectivityPlatform.instance` substitutes headlessly (measured at
/// M4.0/E7), which is what keeps [ConnectivityNetworkStatus] itself covered.
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
  /// SPEC F13 says "before playing", so `PlayerController` calls this once at
  /// start and never subscribes. A mid-playback switch from Wi-Fi to cellular
  /// is out of scope and recorded as debt rather than silently handled.
  Future<NetworkType> current();
}

/// Maps `connectivity_plus`'s transports onto [NetworkType], conservatively.
///
/// **The plugin reports a transport, not a cost, and this is where that gap is
/// made explicit rather than papered over.** Its result set is
/// `{wifi, ethernet, mobile, vpn, bluetooth, satellite, other, none}` — eight
/// values, read off the enum at M4.0 rather than from documentation, and one
/// more than C4 listed — and not one of them says "metered". So:
///
/// - `wifi` and `ethernet` are the only two we can *show* to be unmetered.
/// - everything else, `vpn` and `other` included, is treated as metered.
///   A VPN reports as `vpn` over whatever it is tunnelled through, so the
///   underlying transport is unknowable and the cautious answer is the guarded
///   one.
/// - `none` entries are dropped before the decision; an empty list, or one that
///   is all `none`, is [NetworkType.none].
/// - a list containing `wifi` prefers `wifi`, because the OS reports every
///   active transport and a phone on Wi-Fi with a live cellular radio is on
///   Wi-Fi.
///
/// The residual, and it is the exact case F13 exists for: **a tethered hotspot
/// is reported as `wifi`**, so the guard does not fire.
/// `docs/verification-backlog.md` row 20 carries the device experiment.
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
