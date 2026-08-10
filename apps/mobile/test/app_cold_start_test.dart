import 'dart:async';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// F2's cold start, through the real widget tree.
///
/// Split from `app_test.dart` at M7.3 for `just file-size`. What it proves is
/// the launch path: no saved server, a saved server whose session is gone, a
/// saved server whose session comes back, and the abandoned launch in between.
void main() {
  late Directory dir;
  late FakeLibraryApi api;
  late InMemorySecretStore secrets;
  late List<CertificateFingerprint?> pins;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-cold-');
    api = FakeLibraryApi();
    secrets = InMemorySecretStore();
    pins = [];
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Widget shell() => FileFinScope(
    dependencies: AppDependencies(
      secrets: secrets,
      network: FakeNetworkStatus(),
      playbackHostFactory: fakeHostFactory(),
      nowPlayingFactory: fakeNowPlayingFactory(),
      settings: SettingsStore(dir),
      apiFactory: (_, {pin}) {
        pins.add(pin);
        return api;
      },
    ),
    child: const FileFinApp(),
  );

  void save({ServerId? selected}) {
    final server = SavedServer(
      id: const ServerId('http://nas.local'),
      name: 'Attic NAS',
      baseUrl: Uri.parse('http://nas.local'),
      lastUser: 'sam',
    );
    var settings = AppSettings.empty.upsert(server);
    if (selected != null) settings = settings.withSelected(selected);
    SettingsStore(dir).write(settings);
  }

  testWidgets('with nothing saved it does not even try', (tester) async {
    await tester.pumpWidget(shell());
    await tester.pump();

    expect(api.calls, isEmpty);
    expect(find.text('No server yet'), findsOneWidget);
    expect(find.byKey(const Key('resuming')), findsNothing);
  });

  testWidgets('a stored session lands in the library, no password typed', (
    tester,
  ) async {
    // The whole of F2. Nothing here types anything, and the only thing that
    // differs from the "Signed out" case below is that `restore()` answered.
    save(selected: const ServerId('http://nas.local'));
    api
      ..restoreResult = null
      ..categoriesResult = const <Category>[];
    await tester.pumpWidget(shell());

    expect(
      find.byKey(const Key('resuming')),
      findsOneWidget,
      reason:
          'the launch says it is working rather than showing an empty '
          'state it has not earned',
    );
    await tester.pump();

    expect(api.calls, contains('restore'));
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Attic NAS'), findsOneWidget);
  });

  testWidgets('a restore that fails lands on Signed out, not on a crash', (
    tester,
  ) async {
    // `restoreResult` defaults to `SessionExpired`, which is what a store
    // holding nothing really produces — and `LibraryApi.restore` has already
    // tried F3's silent renewal by the time it throws.
    save(selected: const ServerId('http://nas.local'));
    await tester.pumpWidget(shell());
    await tester.pump();

    expect(api.calls, ['restore']);
    expect(api.closed, isTrue, reason: 'the client it built is released');
    expect(find.text('Signed out'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Sign in'),
      findsOneWidget,
      reason: 'and the server it failed for is the one offered',
    );
  });

  testWidgets('a launch abandoned mid-restore still releases the client', (
    tester,
  ) async {
    // The client is built before anything is known about the session, so a
    // screen that goes away while `restore()` is in flight is a socket
    // nobody closes. `dispose` cannot do it — the client is a local that
    // was never assigned to the state.
    save(selected: const ServerId('http://nas.local'));
    final gate = Completer<void>();
    api
      ..restoreGate = gate
      ..restoreResult = null;
    await tester.pumpWidget(shell());
    await tester.pump();
    expect(api.closed, isFalse);

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();

    expect(api.closed, isTrue);
  });

  testWidgets('a cold start carries F15s accepted pin, not a null one', (
    tester,
  ) async {
    // M7.5 wired the pin into every path that BUILDS a client except this one,
    // and this is the path F2 exists for. Without it a self-signed server —
    // F15's stated common case — fails `restore()` with `CertificateNotTrusted`
    // on every launch, lands on "Signed out", and the user re-types a password
    // the store already holds.
    const accepted =
        '0b:12:19:20:27:2e:35:3c:43:4a:51:58:5f:66:6d:74:'
        '7b:82:89:90:97:9e:a5:ac:b3:ba:c1:c8:cf:d6:dd:e4';
    save(selected: const ServerId('http://nas.local'));
    await secrets.write(
      const ServerId('http://nas.local'),
      SecretKind.certificatePin,
      accepted,
    );
    api
      ..restoreResult = null
      ..categoriesResult = const <Category>[];
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(pins, [CertificateFingerprint.parse(accepted)]);
  });

  testWidgets('a selection naming a server that is gone still launches', (
    tester,
  ) async {
    // The state M7.4's removal leaves behind. Nothing here should strand a
    // launch on an empty screen while a usable server sits in the file.
    save(selected: const ServerId('http://deleted.local'));
    api
      ..restoreResult = null
      ..categoriesResult = const <Category>[];
    await tester.pumpWidget(shell());
    await tester.pump();

    expect(find.text('Attic NAS'), findsOneWidget);
  });
}
