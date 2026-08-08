import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Stands in for the plugin's method channel.
///
/// The same trick `main_test.dart` uses for `PathProviderPlatform`, and it was
/// measured at M4.0/E7 before this file existed rather than assumed: without it
/// `ConnectivityNetworkStatus` would be the first uncovered code in this tree.
final class FakeConnectivityPlatform extends ConnectivityPlatform
    with MockPlatformInterfaceMixin {
  /// What the next `checkConnectivity()` answers.
  List<ConnectivityResult> answer = const [ConnectivityResult.none];

  /// How many times it was asked.
  int checks = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checks++;
    return answer;
  }
}

void main() {
  group('networkTypeOf — a transport is not a cost (C4)', () {
    for (final (name, results, expected)
        in <
          (
            String,
            List<ConnectivityResult>,
            NetworkType,
          )
        >[
          ('wifi', [ConnectivityResult.wifi], NetworkType.wifi),
          ('ethernet', [ConnectivityResult.ethernet], NetworkType.wifi),
          ('mobile', [ConnectivityResult.mobile], NetworkType.metered),
          ('vpn', [ConnectivityResult.vpn], NetworkType.metered),
          ('bluetooth', [ConnectivityResult.bluetooth], NetworkType.metered),
          ('satellite', [ConnectivityResult.satellite], NetworkType.metered),
          ('other', [ConnectivityResult.other], NetworkType.metered),
          ('none', [ConnectivityResult.none], NetworkType.none),
          ('empty', <ConnectivityResult>[], NetworkType.none),
          (
            'wifi and mobile together prefer wifi',
            [ConnectivityResult.mobile, ConnectivityResult.wifi],
            NetworkType.wifi,
          ),
          (
            'vpn over wifi is wifi',
            [ConnectivityResult.vpn, ConnectivityResult.wifi],
            NetworkType.wifi,
          ),
          (
            'vpn over mobile stays metered',
            [ConnectivityResult.vpn, ConnectivityResult.mobile],
            NetworkType.metered,
          ),
          (
            'a none alongside a real transport is dropped',
            [ConnectivityResult.none, ConnectivityResult.mobile],
            NetworkType.metered,
          ),
          (
            'nothing but none is none, however many',
            [ConnectivityResult.none, ConnectivityResult.none],
            NetworkType.none,
          ),
        ]) {
      test('$name -> ${expected.name}', () {
        expect(networkTypeOf(results), expected);
      });
    }

    test('every ConnectivityResult the plugin can return is mapped', () {
      // Read off the enum rather than from documentation, because the plugin
      // gained `satellite` after C4 was written and a value nobody mapped
      // would fall into whichever arm happened to be last.
      expect(ConnectivityResult.values, hasLength(8));
      for (final result in ConnectivityResult.values) {
        expect(
          networkTypeOf([result]),
          isNotNull,
          reason: 'unmapped: $result',
        );
      }
    });
  });

  group('ConnectivityNetworkStatus', () {
    late FakeConnectivityPlatform platform;

    setUp(() {
      platform = FakeConnectivityPlatform();
      ConnectivityPlatform.instance = platform;
    });

    test('asks the platform and maps the answer', () async {
      platform.answer = [ConnectivityResult.mobile];
      expect(await ConnectivityNetworkStatus().current(), NetworkType.metered);
      expect(platform.checks, 1);
    });

    test('samples again each time, rather than caching', () async {
      final status = ConnectivityNetworkStatus();
      platform.answer = [ConnectivityResult.wifi];
      expect(await status.current(), NetworkType.wifi);
      platform.answer = [ConnectivityResult.none];
      expect(await status.current(), NetworkType.none);
      expect(platform.checks, 2);
    });

    test('an injected Connectivity is used instead of the singleton', () async {
      platform.answer = [ConnectivityResult.ethernet];
      final status = ConnectivityNetworkStatus(connectivity: Connectivity());
      expect(await status.current(), NetworkType.wifi);
    });
  });
}
