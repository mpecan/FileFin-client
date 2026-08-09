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
  }) async {
    await tester.pumpWidget(
      FileFinScope(
        dependencies: AppDependencies(
          secrets: secrets,
          network: FakeNetworkStatus(),
          playbackHostFactory: fakeHostFactory(),
          settings: SettingsStore(dir),
          apiFactory: (_, {pin}) => FakeLibraryApi(),
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
