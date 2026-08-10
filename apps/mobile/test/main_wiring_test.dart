import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/main.dart' as entrypoint;
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/platform_secret_store.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `buildApp` actually hands the app, asserted rather than assumed.
///
/// **`main.dart` is production code, and until M7.R nothing observed three of
/// its lines.** `main_test.dart` reads `deps.settings.directory` and invokes
/// `deps.apiFactory`, and never looks at what either is carrying — so three
/// separate one-token mutants survived the whole 1742-test suite:
/// `PlatformSecretStore()` back to `InMemorySecretStore()` (a shipped build
/// that re-prompts for a password every cold start, F2 gone in silence),
/// `pin: pin` back to `pin: null` (M7.5's exact defect restored), and
/// `username:` back to `null` (F3's silent renewal with no account name to
/// renew as). Four tests redden if `apiForServer` drops the pin, and every one
/// of them substitutes a fake factory that only records the fingerprint: the
/// one place the pin reaches a **real** `FileFinClient` is the one place
/// nothing asserted.
///
/// Plain `test()` bodies, not `testWidgets`: the username case needs a real
/// socket to a real `HttpServer`, and a real socket's callback never fires
/// under `FakeAsync` (`library_api_session_test.dart` records the same seam).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  const accepted =
      '0b:12:19:20:27:2e:35:3c:43:4a:51:58:5f:66:6d:74:'
      '7b:82:89:90:97:9e:a5:ac:b3:ba:c1:c8:cf:d6:dd:e4';

  setUpAll(() {
    // flutter_test's binding installs an `HttpOverrides` that answers 400 for
    // everything, so the login below would never reach the stub.
    HttpOverrides.global = null;
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-wiring-');
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  AppDependencies deps() =>
      (entrypoint.buildApp(dir) as FileFinScope).dependencies;

  test('the store it wires is the PLATFORM one, not the in-memory cache', () {
    // The whole of F2's "no password typed on a cold start". An
    // `InMemorySecretStore` here is a shipped build that forgets the password
    // when the process dies, and nothing else in the app would notice.
    expect(deps().secrets, isA<PlatformSecretStore>());
  });

  test('the factory carries F15s pin into a real client', () {
    // `playbackTransport()` is the one thing `LibraryApi` exposes that reads
    // `pinner.pin`, which is what makes this observable from outside the
    // package at all. The unpinned control is what stops the assertion being
    // satisfied by the pin never having existed.
    final server = SavedServer(
      id: const ServerId('https://nas.local'),
      name: 'nas',
      baseUrl: Uri.parse('https://nas.local'),
    );
    final pinned = deps().apiFactory(
      server,
      pin: CertificateFingerprint.parse(accepted),
    );
    addTearDown(pinned.close);
    final unpinned = deps().apiFactory(server);
    addTearDown(unpinned.close);

    expect(pinned.playbackTransport(), PlaybackTransport.pinnedTls);
    expect(unpinned.playbackTransport(), PlaybackTransport.osTrustedTls);
  });

  test('the factory carries lastUser, so F3 knows who to renew as', () async {
    final seen = <String>[];
    final stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => stub.close(force: true));
    unawaited(
      stub.forEach((request) async {
        seen.add(
          '${request.method} ${request.uri.path} '
          '${await utf8.decoder.bind(request).join()}',
        );
        request.response.headers
          ..contentType = ContentType.json
          ..add('set-cookie', 'filefin_session=fresh; Path=/');
        request.response.write('{"user":"sam"}');
        await request.response.close();
      }),
    );

    final built = deps();
    final id = ServerId('http://127.0.0.1:${stub.port}');
    // A password and no session: `restore()` finds nothing to prove, F3's
    // silent renewal is what answers, and `_renew` needs BOTH halves. Without
    // the username it throws `SessionExpired` having sent nothing at all.
    await built.secrets.write(id, SecretKind.password, 'hunter2');
    final api = built.apiFactory(
      SavedServer(
        id: id,
        name: 'stub',
        baseUrl: Uri.parse('http://127.0.0.1:${stub.port}'),
        lastUser: 'sam',
      ),
    );
    addTearDown(api.close);

    await api.restore();

    expect(
      seen,
      contains('POST /api/login {"username":"sam","password":"hunter2"}'),
      reason: 'the account name came from settings.json, not from nowhere',
    );
  });

  test('an empty lastUser stays null rather than logging in as ""', () async {
    // The other arm of the same ternary. A server saved but never signed in to
    // has `lastUser: ''`, and an empty username is a login attempt against a
    // five-failure limiter that cannot ever succeed.
    final seen = <String>[];
    final stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => stub.close(force: true));
    unawaited(
      stub.forEach((request) async {
        seen.add(request.uri.path);
        await request.response.close();
      }),
    );

    final built = deps();
    final id = ServerId('http://127.0.0.1:${stub.port}');
    await built.secrets.write(id, SecretKind.password, 'hunter2');
    final api = built.apiFactory(
      SavedServer(
        id: id,
        name: 'stub',
        baseUrl: Uri.parse('http://127.0.0.1:${stub.port}'),
      ),
    );
    addTearDown(api.close);

    await expectLater(api.restore(), throwsA(isA<SessionExpired>()));
    expect(seen, isEmpty);
  });
}
