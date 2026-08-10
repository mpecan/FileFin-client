import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/add_server_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F15 at the address bar, which is where trust starts.
///
/// Split from `add_server_page_test.dart` for `just file-size`. It shares that
/// file's harness deliberately rather than importing it: what is under test is
/// a different screen behaviour, and a shared harness is a shared reason to
/// change.
void main() {
  late Directory dir;
  late SettingsStore settings;
  late FakeLibraryApi api;
  late InMemorySecretStore secrets;
  late List<CertificateFingerprint?> pins;
  SavedServer? added;

  /// A real SHA-256 shape — `CertificateFingerprint.parse` refuses anything
  /// that is not 64 hex characters.
  const observed =
      '0b:12:19:20:27:2e:35:3c:43:4a:51:58:5f:66:6d:74:'
      '7b:82:89:90:97:9e:a5:ac:b3:ba:c1:c8:cf:d6:dd:e4';

  final untrusted = CertificateNotTrusted(
    Uri.parse('https://nas.local/api/state'),
    fingerprint: observed,
    subject: '/CN=filefin.lan',
    issuer: '/CN=filefin.lan',
    validTo: DateTime.utc(2030),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-add-tls-');
    settings = SettingsStore(dir);
    api = FakeLibraryApi();
    secrets = InMemorySecretStore();
    pins = [];
    added = null;
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    FileFinScope(
      dependencies: AppDependencies(
        secrets: secrets,
        network: FakeNetworkStatus(),
        playbackHostFactory: fakeHostFactory(),
        nowPlayingFactory: fakeNowPlayingFactory(),
        settings: settings,
        apiFactory: (_, {pin}) {
          pins.add(pin);
          return api;
        },
      ),
      child: MaterialApp(
        home: AddServerPage(onAdded: (server) => added = server),
      ),
    ),
  );

  Future<void> type(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(TextField), url);
    await tester.pump();
  }

  Future<void> check(WidgetTester tester) async {
    await tester.tap(find.text('Check this address'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('an untrusted certificate is a QUESTION, not "unreachable"', (
    tester,
  ) async {
    // Until M7.5 `probe()` was never handed a pinner, so this arrived as
    // `ServerUnreachable` and the screen said "Nothing answered at that
    // address" about a self-signed server that had answered — F15's stated
    // common case, reported as the one thing it was not.
    api.probeResult = untrusted;
    await pump(tester);
    await type(tester, 'https://nas.local');

    await check(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('certificate-prompt')), findsOneWidget);
    expect(find.byKey(const Key('certificate-fingerprint')), findsOneWidget);
  });

  testWidgets('accepting pins it and the server is then added', (
    tester,
  ) async {
    api.probeResult = untrusted;
    await pump(tester);
    await type(tester, 'https://nas.local');
    await check(tester);
    await tester.pumpAndSettle();

    api.probeResult = const FileFinServer('0.20.3');
    await tester.tap(find.widgetWithText(FilledButton, 'Trust this server'));
    await tester.pumpAndSettle();

    expect(
      await secrets.read(
        const ServerId('https://nas.local'),
        SecretKind.certificatePin,
      ),
      observed,
    );
    expect(pins, hasLength(2));
    expect(pins.first, isNull);
    expect(pins.last?.value, observed);
    expect(added?.id, const ServerId('https://nas.local'));
  });

  testWidgets('declining stores nothing and names what was refused', (
    tester,
  ) async {
    api.probeResult = untrusted;
    await pump(tester);
    await type(tester, 'https://nas.local');
    await check(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(
      await secrets.read(
        const ServerId('https://nas.local'),
        SecretKind.certificatePin,
      ),
      isNull,
    );
    expect(added, isNull);
    expect(find.byKey(const Key('add-server-problem')), findsOneWidget);
    expect(
      find.textContaining("This server's certificate is not trusted"),
      findsOneWidget,
    );
  });

  testWidgets('a retry that is STILL refused says so and stops', (
    tester,
  ) async {
    // The bound. Exactly two attempts are made, written out rather than
    // looped, so a certificate somehow still untrusted after the pin was
    // written ends in a message rather than in a loop.
    api.probeResult = untrusted;
    await pump(tester);
    await type(tester, 'https://nas.local');
    await check(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Trust this server'));
    await tester.pumpAndSettle();

    expect(pins, hasLength(2));
    expect(find.byKey(const Key('certificate-prompt')), findsNothing);
    expect(find.byKey(const Key('add-server-problem')), findsOneWidget);
    expect(added, isNull);
  });
}
