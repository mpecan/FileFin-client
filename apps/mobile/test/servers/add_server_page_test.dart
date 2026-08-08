import 'dart:convert';
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

void main() {
  late Directory dir;
  late SettingsStore settings;
  late FakeLibraryApi api;
  SavedServer? added;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-add-');
    settings = SettingsStore(dir);
    api = FakeLibraryApi();
    added = null;
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

  testWidgets('a real FileFin server is saved and handed on', (tester) async {
    api.probeResult = const FileFinServer('0.20.3');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(added, isNotNull);
    expect(added!.baseUrl.host, '192.168.1.10');
    expect(settings.read().servers.single.id, added!.id);
  });

  testWidgets('a password typed into the ADDRESS is never saved (§9, NF4)', (
    tester,
  ) async {
    // `https://sam:hunter2@nas.local/` is a thing people type, and
    // `error_presentation.dart` already redacts it out of every message. The
    // persistence path did not: M3 shipped the parsed `Uri` straight into
    // `settings.json`, which is plain JSON any app on a rooted device can
    // read, and `FileFinUrls` then sent it back as a `Basic` header.
    //
    // The assertion is STRUCTURAL — `userInfo` on the decoded URL — rather
    // than a search for the words "password" or "hunter2". The keyword form is
    // what let `sam:hunter2@` through: it contains none of them.
    api.probeResult = const FileFinServer('0.20.3');
    await pump(tester);
    await type(tester, 'http://sam:hunter2@192.168.1.10:8099');

    await check(tester);

    final saved = settings.read().servers.single;
    expect(saved.baseUrl.userInfo, isEmpty);
    expect(saved.baseUrl.host, '192.168.1.10');
    expect(added!.baseUrl.userInfo, isEmpty);
    final text = settings.file.readAsStringSync();
    expect(Uri.parse(_savedBaseUrl(text)).userInfo, isEmpty);
    expect(text, isNot(contains('hunter2')));
  });

  testWidgets('a settings file that cannot be written SAYS so', (tester) async {
    // The screen used to catch `FileFinApiException` and nothing else, so a
    // `FileSystemException` from the write escaped as an unhandled async
    // error: `finally` re-enabled the button, `onAdded` never fired, and no
    // message appeared. Combined with `SettingsStore.read` swallowing every
    // read failure into empty settings, an unwritable support directory was
    // completely invisible — the user adds a server, watches it work, then
    // relaunches and finds it gone.
    //
    // The unwritable directory is made by nesting under a FILE rather than by
    // `chmod`, so the test behaves the same for root and in CI.
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    final wedged = SettingsStore(Directory('${blocker.path}/settings'));
    await tester.pumpWidget(
      FileFinScope(
        dependencies: AppDependencies(
          network: FakeNetworkStatus(),
          playbackHostFactory: fakeHostFactory(),
          settings: wedged,
          apiFactory: (_) => api,
        ),
        child: MaterialApp(
          home: AddServerPage(onAdded: (server) => added = server),
        ),
      ),
    );
    api.probeResult = const FileFinServer('0.20.3');
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(added, isNull);
    expect(_problemText(tester), contains('could not save its settings file'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SavedServer refuses to hold credentials at all', (tester) async {
    // The strip above is one call site; this is what makes it structural. A
    // future screen that builds a `SavedServer` from a typed URL and forgets
    // the strip fails here rather than in `settings.json`.
    //
    // The MESSAGE is pinned verbatim, not merely the type. `just mutants`
    // rewrote `user-typed` to `user+typed` inside it and the whole suite
    // stayed green: an assertion message is mutable source that nothing else
    // reads, so `isA<AssertionError>()` alone lets the sentence rot into
    // nonsense while the test still passes. `error_presentation_test` learned
    // the same thing about `RateLimited`'s wording.
    expect(
      () => SavedServer(
        id: const ServerId('http://nas.local'),
        name: 'nas.local',
        baseUrl: Uri.parse('http://sam:hunter2@nas.local'),
      ),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message,
          'message',
          'A saved baseUrl must not carry userInfo: settings.json is plain '
              'JSON and a user-typed https://user:pass@host is a credential '
              '(§9).',
        ),
      ),
    );
  });

  testWidgets('the saved id is the origin, so re-adding does not duplicate', (
    tester,
  ) async {
    // Two entries for one server would mean two cookie jars, two secret
    // namespaces and two certificate pins — F15 defeated by a second row.
    api.probeResult = const FileFinServer('0.20.3');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099/');
    await check(tester);
    await type(tester, 'http://192.168.1.10:8099');
    await check(tester);

    expect(settings.read().servers, hasLength(1));
  });

  testWidgets('needs-setup is a dead end, not a step, and says so', (
    tester,
  ) async {
    // install.go:22-23 deliberately does not expose the setup token over the
    // API — it reaches a browser only through the URL the CLI prints. So the
    // right thing to show is "finish setup in a browser", never a setup form.
    api.probeResult = const FileFinServerNeedsSetup('0.20.3');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(added, isNull);
    expect(settings.read().servers, isEmpty);
    expect(
      _problemText(tester),
      contains('Finish setup in a browser'),
    );
  });

  testWidgets('not-FileFin names the reason and saves nothing', (tester) async {
    api.probeResult = const NotAFileFinServer('answered text/html, not JSON');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(added, isNull);
    expect(settings.read().servers, isEmpty);
    expect(_problemText(tester), contains('not a FileFin'));
    expect(_problemText(tester), contains('text/html'));
  });

  testWidgets('unreachable is a DIFFERENT message from not-FileFin', (
    tester,
  ) async {
    // The two lead to different actions — check the network versus check the
    // address — and merging them is how a wrong port looks like a wrong
    // product (STATE.md records the same decision inside `filefin_api`).
    api.probeResult = const ServerUnreachable('Connection refused');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(_problemText(tester), contains('Nothing answered'));
    expect(_problemText(tester), contains('Connection refused'));
    expect(_problemText(tester), isNot(contains('not a FileFin')));
  });

  testWidgets('a thrown API failure is described, not swallowed', (
    tester,
  ) async {
    api.probeResult = RequestTimedOut(
      RequestPhase.connect,
      Uri.parse('http://192.168.1.10:8099/api/state'),
    );
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(_problemText(tester), contains('did not answer in time'));
  });

  testWidgets('an http:// address warns, visibly (F15)', (tester) async {
    await pump(tester);

    await type(tester, 'http://192.168.1.10:8099');

    expect(find.byKey(const Key('cleartext-warning')), findsOneWidget);
    expect(find.textContaining('unencrypted'), findsOneWidget);
  });

  testWidgets('the warning names the iOS limitation, not only the risk', (
    tester,
  ) async {
    // NSAllowsLocalNetworking relaxes ATS for LOCAL addressing only, and
    // NSAllowsArbitraryLoads is deliberately not set — so a plain-http server
    // on a public address is refused by the OS. A warning that mentioned only
    // eavesdropping would leave that looking like a broken app.
    await pump(tester);

    await type(tester, 'http://nas.example.com');

    expect(find.textContaining('local network'), findsOneWidget);
  });

  testWidgets('an https:// address does not warn, and still probes', (
    tester,
  ) async {
    // Both halves in one test on purpose. The warning half alone left the
    // `isScheme('https')` arm of the validation unexercised, and `just
    // mutants` said so: negating it survived the whole suite.
    api.probeResult = const FileFinServer('0.20.3');
    await pump(tester);

    await type(tester, 'https://nas.local');
    expect(find.byKey(const Key('cleartext-warning')), findsNothing);

    await check(tester);

    expect(api.calls, ['probeServer']);
    expect(added!.baseUrl.scheme, 'https');
  });

  testWidgets('HTTP:// in capitals warns too', (tester) async {
    // `Uri` lower-cases a scheme, and a user typing capitals is not typing a
    // different protocol. A `startsWith('http://')` check would miss it.
    await pump(tester);

    await type(tester, 'HTTP://nas.local');

    expect(find.byKey(const Key('cleartext-warning')), findsOneWidget);
  });

  testWidgets('a bare hostname is refused before a request is made', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'nas.local');

    await check(tester);

    expect(api.calls, isEmpty);
    expect(_problemText(tester), contains('including http://'));
  });

  testWidgets('the probe carries a cancel token (NF5)', (tester) async {
    api.probeResult = const FileFinServer('0.20.3');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(api.tokens.single, isNotNull);
  });

  testWidgets('the throwaway probe client is closed either way', (
    tester,
  ) async {
    // One client per probe, each with its own socket. Leaking one per typo is
    // how a screen someone retypes an address on runs out of file handles.
    api.probeResult = const NotAFileFinServer('nope');
    await pump(tester);
    await type(tester, 'http://192.168.1.10:8099');

    await check(tester);

    expect(api.closed, isTrue);
  });
}

/// The problem line, read through its key.
///
/// Through the KEY rather than through `find.textContaining`, and `just
/// mutants` is why: with nothing reading the key, rewriting
/// `Key('add-server-problem')` to `Key('add+server-problem')` survived the
/// whole suite. A widget key nothing looks up is a string nothing checks.
String _problemText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('add-server-problem'))).data!;

/// The `baseUrl` the file on disk actually holds, read as JSON rather than
/// grepped — a keyword search is what missed `sam:hunter2@` in the first place.
String _savedBaseUrl(String fileText) =>
    ((jsonDecode(fileText) as Map<String, Object?>)['servers']!
                as List<Object?>)
            .cast<Map<String, Object?>>()
            .single['baseUrl']!
        as String;
