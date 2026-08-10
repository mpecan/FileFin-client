import 'dart:async';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/server_list_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F11's picker: the screen that makes "several servers" reachable.
///
/// The mechanism landed at M2 — `FileFinClient.forServer` gives each
/// `ServerId` its own cookie jar, secret namespace and pinner — and until M7.4
/// nothing could switch between them. What this file pins is the screen; the
/// switch itself is `app_servers_test.dart`, because closing the previous
/// client is `HomeRoute`'s job.
void main() {
  late Directory dir;
  late InMemorySecretStore secrets;

  final attic = SavedServer(
    id: const ServerId('http://attic.local'),
    name: 'Attic NAS',
    baseUrl: Uri.parse('http://attic.local'),
    lastUser: 'sam',
  );
  final work = SavedServer(
    id: const ServerId('https://work.example'),
    name: 'Work',
    baseUrl: Uri.parse('https://work.example'),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-servers-');
    secrets = InMemorySecretStore();
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  void save(AppSettings settings) => SettingsStore(dir).write(settings);

  Future<void> show(
    WidgetTester tester, {
    ServerId? selected,
    void Function(SavedServer server)? onSelect,
    void Function(SavedServer server)? onRemoved,
    VoidCallback? onAdd,
    List<FakeLibraryApi>? built,
    Object? logoutResult,
    Completer<void>? deleteGate,
  }) async {
    await tester.pumpWidget(
      FileFinScope(
        dependencies: AppDependencies(
          secrets: deleteGate == null
              ? secrets
              : _GatedSecrets(secrets, deleteGate),
          network: FakeNetworkStatus(),
          playbackHostFactory: fakeHostFactory(),
          nowPlayingFactory: fakeNowPlayingFactory(),
          settings: SettingsStore(dir),
          // Every client this screen builds, in order — removal now ends the
          // session on the server before it forgets how to prove it, and a
          // factory answering one shared fake could not tell WHICH server it
          // was asked for.
          apiFactory: (server, {pin}) {
            final api = FakeLibraryApi(server: server.id)
              ..logoutResult = logoutResult;
            built?.add(api);
            return api;
          },
        ),
        child: MaterialApp(
          home: ServerListPage(
            selected: selected,
            onSelect: onSelect ?? (_) {},
            onRemoved: onRemoved ?? (_) {},
            onAdd: onAdd ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('every saved server is listed, with the address it is at', (
    tester,
  ) async {
    save(AppSettings.empty.upsert(attic).upsert(work));
    await show(tester);

    expect(find.text('Attic NAS'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    // The address, not only the name: two servers a user called "NAS" are told
    // apart by nothing else, and switching to the wrong one is invisible until
    // the library loads.
    expect(find.text('http://attic.local'), findsOneWidget);
    expect(find.text('https://work.example'), findsOneWidget);
  });

  testWidgets('the selected server is the one marked, not the first', (
    tester,
  ) async {
    // With one saved server a mark on "the first" and a mark on "the selected"
    // are the same widget, so the assertion has to have two — the same reason
    // `selectedServer`'s own `==` needed two to kill its mutant.
    save(AppSettings.empty.upsert(attic).upsert(work));
    await show(tester, selected: work.id);

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Attic NAS'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping a server asks for it by identity', (tester) async {
    save(AppSettings.empty.upsert(attic).upsert(work));
    final chosen = <SavedServer>[];
    await show(tester, selected: attic.id, onSelect: chosen.add);

    await tester.tap(find.text('Work'));
    await tester.pump();

    expect(chosen, [work]);
  });

  testWidgets('removing a server deletes all three of its secrets', (
    tester,
  ) async {
    // §9. Otherwise a password stays in the Keychain for a server no screen can
    // reach, with nothing left that could ever delete it — the store is keyed
    // by `ServerId` and the id has just been forgotten.
    save(AppSettings.empty.upsert(attic).upsert(work));
    for (final kind in SecretKind.values) {
      await secrets.write(work.id, kind, 'work-$kind');
      await secrets.write(attic.id, kind, 'attic-$kind');
    }
    await show(tester);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    for (final kind in SecretKind.values) {
      expect(
        await secrets.read(work.id, kind),
        isNull,
        reason: '$kind outlived the server it belonged to',
      );
      // The other server's are untouched, which is the half a delete-everything
      // would also pass.
      expect(await secrets.read(attic.id, kind), 'attic-$kind');
    }
  });

  testWidgets('removing a server takes it out of settings.json and the list', (
    tester,
  ) async {
    save(AppSettings.empty.upsert(attic).upsert(work).withSelected(work.id));
    final removed = <SavedServer>[];
    await show(tester, selected: work.id, onRemoved: removed.add);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(SettingsStore(dir).read().servers, [attic]);
    expect(SettingsStore(dir).read().selectedServerId, isNull);
    expect(find.text('Work'), findsNothing);
    expect(find.text('Attic NAS'), findsOneWidget);
    expect(removed, [work]);
  });

  testWidgets('a settings write that fails says so and keeps the screen', (
    tester,
  ) async {
    save(AppSettings.empty.upsert(attic).upsert(work));
    await show(tester);
    // The support directory becomes a FILE between the read and the write,
    // which is what a revoked permission or a full disk looks like from here —
    // and, unlike `chmod`, it behaves the same for root and in CI.
    dir.deleteSync(recursive: true);
    File(dir.path).writeAsStringSync('x');
    addTearDown(() {
      File(dir.path).deleteSync();
      dir.createSync(recursive: true);
    });

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-list-problem')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a server ends its session BEFORE forgetting how', (
    tester,
  ) async {
    // Removal deleted three secrets and left the session alive on the server,
    // with nothing left that could ever end it: `logout()` needs the session
    // cookie the removal is about to delete, so it happens first or not at
    // all. The order is the assertion — `close` is in `calls` for exactly this.
    save(AppSettings.empty.upsert(attic).upsert(work));
    final built = <FakeLibraryApi>[];
    await show(tester, built: built);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(built, hasLength(1));
    expect(built.single.server, work.id, reason: 'and the RIGHT server');
    expect(built.single.calls, ['logout', 'close']);
  });

  testWidgets('a server that does not answer is still removed, and says so', (
    tester,
  ) async {
    // Someone whose NAS is unplugged must still be able to forget it.
    // `SessionManager.logout`'s `finally` has already cleared the jar and both
    // secrets by the time it throws, so treating the throw as "still signed
    // in" would leave the app claiming a session neither side holds.
    save(AppSettings.empty.upsert(attic).upsert(work));
    final built = <FakeLibraryApi>[];
    await show(
      tester,
      built: built,
      logoutResult: ConnectionFailed(
        Uri.parse('https://work.example/api/logout'),
        cause: 'connection refused',
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(SettingsStore(dir).read().servers, [attic]);
    expect(find.byKey(const Key('server-list-problem')), findsOneWidget);
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
  });

  testWidgets('the shell is told even when the picker is popped mid-removal', (
    tester,
  ) async {
    // Four real `await`s sit in front of the settings write. Pop the picker
    // during them and the write still committed while `onRemoved` never ran:
    // `settings.json` said `servers: []` and the app went on browsing that
    // server on a live client — and `SignInPage` `upsert`s it straight back at
    // the next sign-in, so the removed server reappears. The `!mounted` guard
    // was on the wrong side of the write.
    save(AppSettings.empty.upsert(attic).upsert(work));
    final gate = Completer<void>();
    final removed = <SavedServer>[];
    await show(tester, onRemoved: removed.add, deleteGate: gate);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pump();
    // The picker goes away while the secret deletes are still in flight.
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();

    expect(SettingsStore(dir).read().servers, [attic]);
    expect(
      removed,
      [work],
      reason: 'the write committed, so the shell must hear about it',
    );
  });

  testWidgets('a settings write that fails has already dropped the pin', (
    tester,
  ) async {
    // §9's ordering, from the side that can tell the two orders apart.
    // `logout()` clears the session and the password itself, so only the
    // certificate pin distinguishes "secrets first" from "settings first" —
    // and with the settings write failing, the other order returns early and
    // leaves the pin behind for a server no screen can reach.
    save(AppSettings.empty.upsert(attic).upsert(work));
    await secrets.write(work.id, SecretKind.certificatePin, 'aa:bb');
    await show(tester);
    dir.deleteSync(recursive: true);
    File(dir.path).writeAsStringSync('x');
    addTearDown(() {
      File(dir.path).deleteSync();
      dir.createSync(recursive: true);
    });

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await secrets.read(work.id, SecretKind.certificatePin), isNull);
    expect(find.byKey(const Key('server-list-problem')), findsOneWidget);
  });

  testWidgets('adding a server is reachable from here', (tester) async {
    // The only way in once a user is signed in: the library shell offers the
    // picker, and the picker is where "another one" lives.
    save(AppSettings.empty.upsert(attic));
    var added = 0;
    await show(tester, onAdd: () => added++);

    await tester.tap(find.text('Add a server'));
    await tester.pump();

    expect(added, 1);
  });

  testWidgets('with nothing saved it says so rather than showing a void', (
    tester,
  ) async {
    await show(tester);

    expect(find.text('No servers saved'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}

/// A store whose DELETES can be held open, so a test can pop the picker while
/// removal is still in flight.
///
/// A gate rather than a delay, for the reason `FakeLibraryApi.writeGate`
/// records: what has to be proved is that the picker went away while the
/// awaits were still running, and a `Duration` under `FakeAsync` would need
/// the test to guess how far to pump.
final class _GatedSecrets extends SecretStore {
  _GatedSecrets(this._inner, this._gate);

  final SecretStore _inner;
  final Completer<void> _gate;

  @override
  Future<String?> read(ServerId server, SecretKind kind) =>
      _inner.read(server, kind);

  @override
  Future<void> write(ServerId server, SecretKind kind, String value) =>
      _inner.write(server, kind, value);

  @override
  Future<void> delete(ServerId server, SecretKind kind) async {
    await _gate.future;
    await _inner.delete(server, kind);
  }
}
