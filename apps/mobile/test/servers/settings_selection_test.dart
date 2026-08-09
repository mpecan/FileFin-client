import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// F11's launch selection: which saved server a cold start opens, and what
/// happens to that answer when one is removed.
///
/// Split out of `settings_store_test.dart` at M7.4, when removal pushed that
/// file past `just file-size`'s soft limit. They are one subject: `servers`,
/// `selectedServerId` and the fallback between them.
///
/// **Two saved servers, not one, in every case that can tell them apart.** With
/// one server the fallback returns the object a match would have returned, so
/// `==` and `!=` in the lookup are the same green run — `just mutants` found
/// exactly that survivor at M7.3.
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
    dir = Directory.systemTemp.createTempSync('filefin-selection-');
    store = SettingsStore(dir);
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('nothing is selected before the first sign-in', () {
    store.write(AppSettings.empty.upsert(home));

    expect(store.read().selectedServerId, isNull);
  });

  test('the selection round-trips through the file', () {
    store.write(AppSettings.empty.upsert(home).withSelected(home.id));

    expect(store.read().selectedServerId, home.id);
    expect(store.read().selectedServer, home);
  });

  test('an unselected list still offers a server to launch into', () {
    // Not a stand-in for the picker: it is what stops a first launch after
    // adding a server — where nothing has been selected yet — landing on an
    // empty screen with a saved server sitting in the file.
    store.write(AppSettings.empty.upsert(home));

    expect(store.read().selectedServer, home);
  });

  test('with two saved, the SELECTED one is chosen, not the first', () {
    // The case the whole field exists for, and the only one that can tell
    // `==` from `!=` in the lookup: with one saved server both answer it,
    // because the fallback below returns the same object the match would
    // have. `just mutants` found exactly that survivor.
    final other = SavedServer(
      id: const ServerId('attic'),
      name: 'Attic',
      baseUrl: Uri.parse('http://attic.local'),
    );
    store.write(
      AppSettings.empty.upsert(home).upsert(other).withSelected(other.id),
    );

    expect(store.read().selectedServer, other);
    expect(store.read().servers.first, home);
  });

  test('a selection naming a server that is gone falls back', () {
    // The case M7.4's removal produces. Without the fallback, deleting the
    // selected server strands every later launch.
    final other = SavedServer(
      id: const ServerId('attic'),
      name: 'Attic',
      baseUrl: Uri.parse('http://attic.local'),
    );
    store.write(
      AppSettings.empty.upsert(other).withSelected(const ServerId('gone')),
    );

    expect(store.read().selectedServer, other);
  });

  test('nothing saved means nothing to launch into', () {
    expect(store.read().selectedServer, isNull);
  });

  test('removing the SELECTED server clears the selection with it', () {
    // Leaving the id behind would be harmless only because
    // `selectedServer`'s fallback covers it. It is still a dangling
    // reference written to disk, and re-adding a server at the same origin
    // would silently select it again — a server the user removed coming
    // back as the launch target.
    final other = SavedServer(
      id: const ServerId('attic'),
      name: 'Attic',
      baseUrl: Uri.parse('http://attic.local'),
    );
    final saved = AppSettings.empty
        .upsert(home)
        .upsert(other)
        .withSelected(other.id);

    final left = saved.remove(other.id);

    expect(left.servers, [home]);
    expect(left.selectedServerId, isNull);
  });

  test('removing a DIFFERENT server leaves the selection alone', () {
    final other = SavedServer(
      id: const ServerId('attic'),
      name: 'Attic',
      baseUrl: Uri.parse('http://attic.local'),
    );
    final saved = AppSettings.empty
        .upsert(home)
        .upsert(other)
        .withSelected(other.id);

    final left = saved.remove(home.id);

    expect(left.servers, [other]);
    expect(left.selectedServerId, other.id);
  });

  test('a removal round-trips through the file, playback intact', () {
    final saved = AppSettings.empty
        .upsert(home)
        .withSelected(home.id)
        .withPlayback(const PlaybackPrefs(progressIntervalSecs: 45));
    store.write(saved.remove(home.id));

    final read = store.read();

    expect(read.servers, isEmpty);
    expect(read.selectedServerId, isNull);
    expect(read.playback.progressIntervalSecs, 45);
  });

  test('the selection survives upsert and a playback change', () {
    // Both copy constructors used to drop whatever field they did not name,
    // and this one is read on every launch — so a settings-sheet toggle that
    // silently cleared it would send the next launch to a different server.
    final saved = AppSettings.empty.upsert(home).withSelected(home.id);

    expect(saved.upsert(home).selectedServerId, home.id);
    expect(
      saved.withPlayback(const PlaybackPrefs()).selectedServerId,
      home.id,
    );
  });
}
