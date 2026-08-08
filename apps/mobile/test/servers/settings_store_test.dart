import 'dart:convert';
import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late SettingsStore store;

  final home = SavedServer(
    id: const ServerId('home'),
    name: 'Home NAS',
    baseUrl: Uri.parse('http://192.168.1.10:8099'),
    lastUser: 'sam',
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-settings-');
    store = SettingsStore(dir);
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('nothing saved yet reads as empty, not as an error', () {
    expect(store.read().servers, isEmpty);
  });

  test('a server round-trips through a real file', () {
    store.write(AppSettings.empty.upsert(home));

    final read = store.read();

    expect(read.servers, [home]);
    expect(read.servers.single.baseUrl.host, '192.168.1.10');
    expect(read.servers.single.lastUser, 'sam');
  });

  test('write creates the directory if it is not there', () {
    // A first launch reaches this before anything else has written to the
    // application support directory, and on iOS it does not exist yet.
    final nested = Directory('${dir.path}/does/not/exist');
    SettingsStore(nested).write(AppSettings.empty);

    expect(nested.existsSync(), isTrue);
  });

  test('upsert replaces by id rather than appending a duplicate', () {
    final store2 = SettingsStore(
      dir,
    )..write(AppSettings.empty.upsert(home).upsert(home.withLastUser('kim')));

    final servers = store2.read().servers;

    expect(servers, hasLength(1));
    expect(servers.single.lastUser, 'kim');
  });

  test('upsert keeps the order servers were added in', () {
    final other = SavedServer(
      id: const ServerId('work'),
      name: 'Work',
      baseUrl: Uri.parse('https://work.example'),
    );
    store.write(AppSettings.empty.upsert(home).upsert(other));

    expect(store.read().servers.map((s) => s.id.value), ['home', 'work']);
  });

  test('a corrupt file is empty settings, not a crash', () {
    // §13: our own format changes freely before release, so a file an older
    // build wrote is not something to migrate — it is something to replace.
    // Losing a server list costs a user a retype; refusing to launch costs
    // them the app.
    store.file
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json at all');

    expect(store.read().servers, isEmpty);
  });

  test('a file of the wrong SHAPE is empty settings too', () {
    // Valid JSON, wrong structure — which is what an older build's file looks
    // like. The strict decoder throws and this is what catches it.
    store.file
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'servers': 'not a list'}));

    expect(store.read().servers, isEmpty);
  });

  test(
    'a server entry missing a key is empty settings, not a partial read',
    () {
      // A half-read entry is worse than none: it would produce a server with a
      // blank URL that fails at the first request with no explanation.
      store.file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'servers': [
              {'id': 'home', 'name': 'Home'},
            ],
          }),
        );

      expect(store.read().servers, isEmpty);
    },
  );

  test('the file holds no password, session or pin (§9)', () {
    // The one assertion that matters most in this file. `settings.json` is
    // plain JSON any app on a rooted device can read.
    //
    // The `userInfo` arm is STRUCTURAL rather than a keyword search, and that
    // is the whole lesson of M3's review: this test used to grep the text for
    // "password", "session" and "certpin", and a real leaked credential —
    // `"baseUrl":"http://sam:hunter2@192.168.1.10:8099"` — contains none of
    // the three. A field is checked by what it can carry, not by what it
    // happens to be spelled.
    store.write(
      AppSettings.empty
          .upsert(home)
          .upsert(
            SavedServer.fromTypedUrl(
              Uri.parse('http://sam:hunter2@192.168.1.10:9000'),
            ),
          ),
    );

    final raw = store.file.readAsStringSync();
    final text = raw.toLowerCase();
    final decoded = jsonDecode(raw)! as Map<String, Object?>;
    final entries = (decoded['servers']! as List<Object?>)
        .cast<Map<String, Object?>>();

    for (final entry in entries) {
      expect(Uri.parse(entry['baseUrl']! as String).userInfo, isEmpty);
    }
    expect(text, isNot(contains('hunter2')));
    expect(text, isNot(contains('password')));
    expect(text, isNot(contains('session')));
    expect(text, isNot(contains('certpin')));
    expect(text, contains('lastuser'));
  });

  test(
    'SavedServer and AppSettings compare and print by value',
    () {
      expect(home, equals(home.withLastUser('sam')));
      expect(home, isNot(equals(home.withLastUser('kim'))));
      expect(home.hashCode, home.withLastUser('sam').hashCode);
      expect(home.toString(), contains('Home NAS'));
      expect(
        AppSettings.empty.upsert(home).toString(),
        'AppSettings(1 server(s))',
      );
    },
  );
}
