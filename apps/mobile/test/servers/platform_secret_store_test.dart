import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/servers/platform_secret_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// `PlatformSecretStore` against the plugin's own headless seam.
///
/// `FlutterSecureStorage.setMockInitialValues` installs
/// `TestFlutterSecureStoragePlatform`, which keeps **the map it is handed** —
/// so `platform` below is the other side of the boundary rather than a
/// reimplementation of it, and asserting on it is asserting on the exact keys
/// and values that crossed. Measured at M7.0/E-4: the plain call throws
/// `MissingPluginException` under `flutter test` and this seam is what replaces
/// it, so the wrapper is covered headlessly and the uncovered ratchet stays 0.
void main() {
  late Map<String, String> platform;
  late PlatformSecretStore store;

  const home = ServerId('https://nas.local');
  const away = ServerId('https://attic.example');

  setUp(() {
    platform = {};
    FlutterSecureStorage.setMockInitialValues(platform);
    store = PlatformSecretStore();
  });

  test('the keys crossing the boundary are SPEC §7 s layout', () async {
    await store.write(home, SecretKind.session, 'sess-1');
    await store.write(home, SecretKind.password, 'hunter2');
    await store.write(home, SecretKind.certificatePin, 'aa:bb');

    expect(platform.keys, [
      'filefin/https://nas.local/session',
      'filefin/https://nas.local/password',
      'filefin/https://nas.local/certpin',
    ]);
  });

  test('a written value is read from memory, not the platform', () async {
    await store.write(home, SecretKind.password, 'hunter2');
    // The platform copy is removed behind the store's back. A read that still
    // answers can only have come from memory — which is what F3's 401 retry
    // needs, because a Keychain read can block on a locked device.
    platform.clear();

    expect(await store.read(home, SecretKind.password), 'hunter2');
  });

  test('a cold start reads through to the platform, then caches', () async {
    // Nothing was written this process: this is the launch after an app
    // restart, which is the whole of F2's persistence half.
    platform['filefin/https://nas.local/password'] = 'hunter2';

    expect(await store.read(home, SecretKind.password), 'hunter2');
    platform.clear();
    expect(
      await store.read(home, SecretKind.password),
      'hunter2',
      reason: 'the first read populated memory',
    );
  });

  test('a missing secret is null, not an error', () async {
    expect(await store.read(home, SecretKind.session), isNull);
  });

  test('delete removes it from BOTH sides', () async {
    await store.write(home, SecretKind.session, 'sess-1');

    await store.delete(home, SecretKind.session);

    expect(platform, isEmpty);
    expect(await store.read(home, SecretKind.session), isNull);
  });

  test(
    'two servers never see each other s secrets, across a restart',
    () async {
      // The one test F11 rests on, and the restart is what makes it real. Read
      // through the same store the writes went through and the in-memory layer
      // answers every one of them, so a key that ignored the server entirely
      // still looked correct: hard-coding a constant `ServerId` in
      // `secretKeyFor`'s caller left this case GREEN. The second store shares
      // only the platform map, which is exactly what a second launch shares.
      await store.write(home, SecretKind.password, 'home-pw');
      await store.write(away, SecretKind.password, 'away-pw');
      final afterRestart = PlatformSecretStore();

      expect(await afterRestart.read(home, SecretKind.password), 'home-pw');
      expect(await afterRestart.read(away, SecretKind.password), 'away-pw');
      await afterRestart.delete(home, SecretKind.password);
      expect(await afterRestart.read(home, SecretKind.password), isNull);
      expect(
        await PlatformSecretStore().read(away, SecretKind.password),
        'away-pw',
        reason: 'deleting one server s secret must not touch another s',
      );
    },
  );

  test('it prints nothing it holds', () async {
    await store.write(home, SecretKind.password, 'hunter2');

    expect('$store', 'PlatformSecretStore(<redacted>)');
    expect('$store', isNot(contains('hunter2')));
  });
}
