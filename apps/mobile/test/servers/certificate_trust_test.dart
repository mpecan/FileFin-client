import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/servers/sign_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F15's accept-and-pin loop, through the app — which never had one.
///
/// Every pure piece landed at M2 and was table-tested: `decidePin` over all
/// twelve combinations, both TLS hooks, the error variants, and the words that
/// name subject, fingerprint and both values on a change. Nothing joined them
/// to a user. `main.dart` called `FileFinClient.forServer` and never passed
/// `pin:`, so every shipped client ran `CertificatePinner(pin: null)`; a
/// self-signed server — F15's stated common case — showed an unactionable
/// error for ever, and `RejectChanged` could not fire in a shipped binary
/// because no pin was ever stored. `SecretKind.certificatePin` had zero
/// production reads and zero writes.
void main() {
  late Directory dir;
  late FakeLibraryApi api;
  late InMemorySecretStore secrets;
  late List<CertificateFingerprint?> pins;

  final server = SavedServer(
    id: const ServerId('https://nas.local'),
    name: 'Attic NAS',
    baseUrl: Uri.parse('https://nas.local'),
    lastUser: 'sam',
  );

  /// A real SHA-256 shape: `CertificateFingerprint.parse` refuses anything
  /// that is not 64 hex characters, which is what stops a mistyped pin
  /// becoming a value that quietly matches nothing for ever.
  const observed =
      '0b:12:19:20:27:2e:35:3c:43:4a:51:58:5f:66:6d:74:'
      '7b:82:89:90:97:9e:a5:ac:b3:ba:c1:c8:cf:d6:dd:e4';
  const wasPinned =
      '03:10:1d:2a:37:44:51:5e:6b:78:85:92:9f:ac:b9:c6:'
      'd3:e0:ed:fa:07:14:21:2e:3b:48:55:62:6f:7c:89:96';

  final untrusted = CertificateNotTrusted(
    Uri.parse('https://nas.local/api/login'),
    fingerprint: observed,
    subject: '/CN=filefin.lan',
    issuer: '/CN=filefin.lan',
    validTo: DateTime.utc(2030),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-tls-');
    api = FakeLibraryApi();
    secrets = InMemorySecretStore();
    pins = [];
    SettingsStore(dir).write(AppSettings.empty.upsert(server));
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Widget signIn() => MaterialApp(
    home: FileFinScope(
      dependencies: AppDependencies(
        settings: SettingsStore(dir),
        secrets: secrets,
        network: FakeNetworkStatus(),
        playbackHostFactory: fakeHostFactory(),
        // Every pin the app resolved, in order. The SECOND one is the whole
        // point: a client rebuilt without it would connect exactly as
        // unpinned as the first.
        apiFactory: (_, {pin}) {
          pins.add(pin);
          return api;
        },
      ),
      child: SignInPage(
        server: server,
        onSignedIn: (_, _) {},
      ),
    ),
  );

  Future<void> attempt(WidgetTester tester) async {
    await tester.pumpWidget(signIn());
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('an untrusted certificate is shown, not swallowed', (
    tester,
  ) async {
    api.loginResult = untrusted;

    await attempt(tester);

    expect(find.byKey(const Key('certificate-prompt')), findsOneWidget);
    expect(
      find.byKey(const Key('certificate-fingerprint')),
      findsOneWidget,
      reason: 'the fingerprint is the one thing a user can compare',
    );
    expect(find.textContaining(observed), findsWidgets);
    expect(find.textContaining('/CN=filefin.lan'), findsOneWidget);
  });

  testWidgets('accepting writes the pin and signs in with it', (tester) async {
    // The loop, end to end. The second attempt is made by a client built with
    // the pin the first attempt could not have had.
    api.loginResult = untrusted;
    await attempt(tester);

    api.loginResult = const AuthResult(user: 'sam');
    await tester.tap(find.widgetWithText(FilledButton, 'Trust this server'));
    await tester.pumpAndSettle();

    expect(
      await secrets.read(server.id, SecretKind.certificatePin),
      observed,
    );
    expect(pins, hasLength(2));
    expect(pins.first, isNull, reason: 'the first attempt had nothing to pin');
    expect(pins.last?.value, observed);
    expect(find.byKey(const Key('sign-in-problem')), findsNothing);
  });

  testWidgets('declining stores nothing and says what was refused', (
    tester,
  ) async {
    api.loginResult = untrusted;
    await attempt(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await secrets.read(server.id, SecretKind.certificatePin), isNull);
    expect(pins, hasLength(1));
    expect(find.byKey(const Key('sign-in-problem')), findsOneWidget);
    expect(
      find.textContaining("This server's certificate is not trusted"),
      findsOneWidget,
    );
  });

  testWidgets('a CHANGED certificate offers no accept path at all', (
    tester,
  ) async {
    // F15's loud half, and the one that must never soften into a prompt.
    // `decidePin` never updates a pin and neither may a screen: re-accepting
    // silently is the whole thing pinning exists to prevent.
    api.loginResult = CertificatePinMismatch(
      Uri.parse('https://nas.local/api/login'),
      expected: wasPinned,
      actual: observed,
    );

    await attempt(tester);

    expect(find.byKey(const Key('certificate-prompt')), findsNothing);
    expect(find.text('Trust this server'), findsNothing);
    expect(
      find.textContaining("This server's certificate has changed"),
      findsOneWidget,
    );
    expect(find.textContaining(wasPinned), findsOneWidget);
    expect(find.textContaining(observed), findsOneWidget);
    expect(await secrets.read(server.id, SecretKind.certificatePin), isNull);
  });

  testWidgets('a retry that is STILL refused says so and stops', (
    tester,
  ) async {
    // The bound, and it is structural rather than conditional: two attempts
    // written out cannot be rewritten into a loop by a mutant, which is the
    // hang CLAUDE.md describes.
    api.loginResult = untrusted;
    await attempt(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Trust this server'));
    await tester.pumpAndSettle();

    expect(pins, hasLength(2));
    expect(find.byKey(const Key('certificate-prompt')), findsNothing);
    expect(find.byKey(const Key('sign-in-problem')), findsOneWidget);
  });

  testWidgets('a stored pin is carried into the client from the start', (
    tester,
  ) async {
    // The other half of the loop: a server accepted earlier connects with its
    // pin without asking again.
    await secrets.write(
      server.id,
      SecretKind.certificatePin,
      observed,
    );
    api.loginResult = const AuthResult(user: 'sam');

    await attempt(tester);

    expect(pins.single?.value, observed);
    expect(find.byKey(const Key('certificate-prompt')), findsNothing);
  });
}
