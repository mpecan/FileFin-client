import 'dart:async';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/launch_pages.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/shell/form_factor.dart';
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
    child: const FileFinApp(formFactor: FormFactor.phone),
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

  /// The launch screen's icon, its colour, and the two strings — which is how
  /// a user tells a failed launch from an ordinary signed-out one before
  /// reading a word.
  ///
  /// Both keys and both branches of the icon/colour ternary were mutable with
  /// nothing objecting: `problem == null` -> `!=` swapped the icon and the
  /// colour, and `Key('launch-headline')` -> `Key('launch+headline')` changed a
  /// key no test looked up. Four survivors, all here.
  (IconData, Color, String, String) launchScreen(WidgetTester tester) {
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(NoServerPage),
        matching: find.byType(Icon),
      ),
    );
    return (
      icon.icon!,
      icon.color!,
      tester.widget<Text>(find.byKey(const Key('launch-headline'))).data!,
      tester.widget<Text>(find.byKey(const Key('launch-detail'))).data!,
    );
  }

  ColorScheme colours(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(NoServerPage))).colorScheme;

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

    // The close is in the record now, and it is the half that matters here:
    // the client was built before anything was known about the session.
    expect(api.calls, ['restore', 'close']);
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

  testWidgets('a CHANGED certificate says so, and offers NO sign-in', (
    tester,
  ) async {
    // The event F15 exists to make visible, on the one path that used to hide
    // it. `_resume` caught every `FileFinApiException` and rendered the same
    // silent "Signed out — your password is in the secure store", which is an
    // invitation to retype a password at a server whose identity has just
    // failed. `describeApiError` had the words all along; nothing called them.
    save(selected: const ServerId('http://nas.local'));
    api.restoreResult = CertificatePinMismatch(
      Uri.parse('http://nas.local/api/me'),
      expected: 'aa:bb',
      actual: 'cc:dd',
    );
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    final (icon, colour, headline, detail) = launchScreen(tester);
    expect(icon, Icons.gpp_maybe_outlined);
    expect(colour, colours(tester).error);
    expect(headline, "This server's certificate has changed");
    expect(detail, allOf(contains('aa:bb'), contains('cc:dd')));
    expect(
      find.widgetWithText(FilledButton, 'Sign in'),
      findsNothing,
      reason: 'F15 calls a changed certificate a rejection, not another prompt',
    );
    // The two ways out are still there, which is what stops the rejection
    // being a dead end.
    expect(find.widgetWithText(TextButton, 'Servers'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add a server'), findsOneWidget);
  });

  testWidgets('a server that is merely OFF does not claim you signed out', (
    tester,
  ) async {
    save(selected: const ServerId('http://nas.local'));
    api.restoreResult = ConnectionFailed(
      Uri.parse('http://nas.local/api/me'),
      cause: 'connection refused',
    );
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server'), findsOneWidget);
    expect(find.text('Signed out'), findsNothing);
    // Still offered here, unlike the certificate case: a server that is off
    // comes back, and there is nothing suspicious about typing a password at
    // it once it does.
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('an ORDINARY expiry keeps the wording F2 wrote for it', (
    tester,
  ) async {
    // The control for the two above: `SessionExpired` is the common outcome
    // and the signed-out screen already says the right thing about it, so it
    // must NOT be replaced by `describeApiError`'s more clinical sentence.
    save(selected: const ServerId('http://nas.local'));
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    final (icon, colour, headline, detail) = launchScreen(tester);
    expect(
      icon,
      Icons.dns_outlined,
      reason: 'nothing is wrong with the server',
    );
    expect(colour, colours(tester).primary);
    expect(headline, 'Signed out');
    expect(detail, contains("device's secure store"));
  });

  testWidgets('an unreadable stored pin does not brick the launch', (
    tester,
  ) async {
    // `CertificateFingerprint.parse` throws a raw `ArgumentError`, and
    // `apiForServer` is called OUTSIDE `_resume`'s try — which catches only
    // `FileFinApiException`. So one unreadable byte in the Keychain hung every
    // launch for ever: `_resuming` never cleared, `ResumingPage` is a bare
    // spinner with no button, and `_launched` latches. There was no route left
    // to the picker, to add-server or to sign-out.
    save(selected: const ServerId('http://nas.local'));
    await secrets.write(
      const ServerId('http://nas.local'),
      SecretKind.certificatePin,
      'this is not a fingerprint',
    );
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resuming')), findsNothing);
    expect(find.text('Signed out'), findsOneWidget);
    expect(pins, [isNull], reason: 'the client was built, and built unpinned');
    expect(
      await secrets.read(
        const ServerId('http://nas.local'),
        SecretKind.certificatePin,
      ),
      isNull,
      reason:
          'a value nothing can ever read again is deleted, so the next '
          'connection is F15s prompt rather than a protection that lapsed',
    );
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
