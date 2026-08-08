import 'dart:async';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/servers/sign_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late Directory dir;
  late SettingsStore settings;
  late FakeLibraryApi api;
  LibraryApi? handedOn;

  final server = SavedServer(
    id: const ServerId('http://nas.local:8099'),
    name: 'nas.local',
    baseUrl: Uri.parse('http://nas.local:8099'),
    lastUser: 'sam',
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-signin-');
    settings = SettingsStore(dir)..write(AppSettings.empty.upsert(server));
    api = FakeLibraryApi();
    handedOn = null;
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    FileFinScope(
      dependencies: AppDependencies(
        network: FakeNetworkStatus(),
        playbackHostFactory: fakeHostFactory(),
        settings: settings,
        apiFactory: (_) => api,
      ),
      child: MaterialApp(
        home: SignInPage(
          server: server,
          onSignedIn: (_, signedIn) => handedOn = signedIn,
        ),
      ),
    ),
  );

  Future<void> submit(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField).last, password);
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the username is prefilled from lastUser', (tester) async {
    // Not a secret, and a cold start needs it for F2's silent renewal — so
    // making someone retype it every time buys nothing.
    await pump(tester);

    expect(find.text('sam'), findsOneWidget);
  });

  testWidgets('a successful sign-in hands the API on and records the user', (
    tester,
  ) async {
    api.loginResult = const AuthResult(user: 'sam');
    await pump(tester);

    await submit(tester, 'hunter2');

    expect(identical(handedOn, api), isTrue);
    expect(settings.read().servers.single.lastUser, 'sam');
  });

  testWidgets('the password never reaches settings.json (§9, NF4)', (
    tester,
  ) async {
    api.loginResult = const AuthResult(user: 'sam');
    await pump(tester);

    await submit(tester, 'hunter2');

    expect(settings.file.readAsStringSync(), isNot(contains('hunter2')));
  });

  testWidgets('a settings file that cannot be written SAYS so', (tester) async {
    // Same hole as the add-server screen: only `FileFinApiException` was
    // caught, so a write failure vanished into an unhandled async error with
    // the button re-enabled and nothing on screen.
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    api.loginResult = const AuthResult(user: 'sam');
    await tester.pumpWidget(
      FileFinScope(
        dependencies: AppDependencies(
          network: FakeNetworkStatus(),
          playbackHostFactory: fakeHostFactory(),
          settings: SettingsStore(Directory('${blocker.path}/settings')),
          apiFactory: (_) => api,
        ),
        child: MaterialApp(
          home: SignInPage(
            server: server,
            onSignedIn: (_, signedIn) => handedOn = signedIn,
          ),
        ),
      ),
    );

    await submit(tester, 'hunter2');

    expect(handedOn, isNull);
    expect(api.closed, isTrue);
    expect(
      tester.widget<Text>(find.byKey(const Key('sign-in-problem'))).data,
      contains('could not save its settings file'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bad credentials do not claim to know which of the three', (
    tester,
  ) async {
    // auth.go:157-169 runs exactly one bcrypt compare against a dummy hash
    // when the account does not exist, so neither the body nor the timing
    // separates wrong-password from unknown-account from locked.
    api.loginResult = InvalidCredentials(server.baseUrl);
    await pump(tester);

    await submit(tester, 'wrong');

    final text = tester
        .widget<Text>(find.byKey(const Key('sign-in-problem')))
        .data!
        .toLowerCase();
    expect(text, contains('refused'));
    expect(text, isNot(contains('no such user')));
    expect(handedOn, isNull);
  });

  testWidgets('a rate limit names the seconds it was told to wait', (
    tester,
  ) async {
    api.loginResult = RateLimited(
      const Duration(seconds: 900),
      server.baseUrl,
      rawRetryAfter: '900',
    );
    await pump(tester);

    await submit(tester, 'wrong');

    expect(find.textContaining('900 seconds'), findsOneWidget);
  });

  testWidgets('the keyboard Done key submits, like the button does', (
    tester,
  ) async {
    // A password field a user cannot submit from the keyboard is a field they
    // have to dismiss the keyboard to leave.
    api.loginResult = const AuthResult(user: 'sam');
    await pump(tester);
    await tester.enterText(find.byType(TextField).last, 'hunter2');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(identical(handedOn, api), isTrue);
  });

  testWidgets(
    'a sign-in that lands after the screen closes closes the client',
    (
      tester,
    ) async {
      // NF5's other half: a socket opened for a screen that is gone is a leak
      // nothing else will notice. Left unclosed it is one file handle per
      // abandoned sign-in.
      final gate = Completer<AuthResult>();
      final slow = _SlowLoginApi(gate.future);
      await tester.pumpWidget(
        FileFinScope(
          dependencies: AppDependencies(
            network: FakeNetworkStatus(),
            playbackHostFactory: fakeHostFactory(),
            settings: settings,
            apiFactory: (_) => slow,
          ),
          child: MaterialApp(
            home: SignInPage(server: server, onSignedIn: (_, _) {}),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'hunter2');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gate.complete(const AuthResult(user: 'sam'));
      await tester.pump();

      expect(slow.closed, isTrue);
    },
  );

  testWidgets('a failed sign-in closes the client it built', (tester) async {
    api.loginResult = InvalidCredentials(server.baseUrl);
    await pump(tester);

    await submit(tester, 'wrong');

    expect(api.closed, isTrue);
  });

  group('the 401 discipline — a 401 is not a sign-in prompt', () {
    // THE RULE, named so the tempting bug is named too. A 401 on any call is
    // routine (SPEC.md L1): server sessions live in memory and die with the
    // process. `filefin_api` re-authenticates and retries once (F3), and the
    // caller never sees the 401 at all. Only a `SessionExpired` — which means
    // that retry ALSO failed — is a reason to ask for a password.
    //
    // A UI-level 401 handler would prompt every time a server restarted
    // mid-scroll, which is exactly the experience F2 and F3 exist to prevent.

    testWidgets(
      'a call that succeeded after a transparent retry prompts nobody',
      (
        tester,
      ) async {
        // The fake returns a value, which is what the caller sees when
        // `AuthInterceptor` has already renewed and replayed. Nothing about
        // that path is visible from here — and nothing should be.
        final browse = FakeLibraryApi()..categoriesResult = <Category>[];
        final controller = AsyncController<List<Category>>(
          (token) => browse.categories(cancelToken: token),
        );
        addTearDown(controller.dispose);
        var signInsOffered = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AsyncView<List<Category>>(
              controller: controller,
              onSignIn: () => signInsOffered += 1,
              builder: (_, value) => Text('${value.length} categories'),
            ),
          ),
        );

        await controller.load();
        await tester.pump();

        expect(find.text('0 categories'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
        expect(signInsOffered, 0);
      },
    );

    testWidgets('only a thrown SessionExpired offers sign-in', (tester) async {
      final browse = FakeLibraryApi()
        ..categoriesResult = SessionExpired(server.baseUrl);
      final controller = AsyncController<List<Category>>(
        (token) => browse.categories(cancelToken: token),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AsyncView<List<Category>>(
            controller: controller,
            onSignIn: () {},
            builder: (_, value) => Text('${value.length} categories'),
          ),
        ),
      );

      await controller.load();
      await tester.pump();

      expect(find.text('Sign in'), findsOneWidget);
    });
  });
}

/// A fake whose `login` completes only when the test says so, so a screen can
/// be disposed with a request still in flight.
final class _SlowLoginApi extends FakeLibraryApi {
  _SlowLoginApi(this._gate);

  final Future<AuthResult> _gate;

  @override
  Future<AuthResult> login(Credentials credentials) => _gate;
}
