import 'dart:io';

import 'package:filefin_mobile/src/playback/ca_bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trust store libmpv is handed, both answers and every way each fails.
///
/// Nothing here is guarded on the host platform. `CaBundle` reaches its two
/// answers through a channel and an [AssetBundle], so a runner reporting macOS
/// exercises the same arms an Android or iOS device takes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  var calls = 0;

  void answer(Future<Object?>? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(CaBundle.channel, (call) {
      calls += 1;
      return handler(call);
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(CaBundle.channel, null),
    );
  }

  setUp(() {
    calls = 0;
    CaBundle.reset();
    // Both are process-wide, so a test that sets one and a test that reads it
    // would otherwise depend on the order they happen to run in.
    CaBundle.cacheDirectory = null;
    CaBundle.assets = rootBundle;
  });

  test('the exported path is what the host answered with', () async {
    answer((call) async => '/data/cache/ca.pem');

    expect(await CaBundle.path, '/data/cache/ca.pem');
  });

  /// One trust store per process. Re-exporting on every open would write a
  /// file per playback, and the cache is what stops it.
  test('it exports once, however often it is asked', () async {
    answer((call) async => '/data/cache/ca.pem');

    await CaBundle.path;
    await CaBundle.path;
    await CaBundle.path;

    expect(calls, 1);
  });

  /// A host with no handler and nowhere to write still has to answer, and the
  /// answer is null rather than a throw.
  test('no handler and no cache directory is null, not an error', () async {
    CaBundle.cacheDirectory = null;

    expect(await CaBundle.path, isNull);
  });

  /// An empty string means the KeyStore held nothing. Handing mpv a path to an
  /// empty file is worse than handing it none: `tls-verify` would then trust
  /// nothing at all.
  test('an empty answer is treated as no bundle', () async {
    answer((call) async => '');

    expect(await CaBundle.path, isNull);
  });

  test('the method it asks for is the one MainActivity answers', () async {
    final asked = <String>[];
    answer((call) async {
      asked.add(call.method);
      return '/data/cache/ca.pem';
    });

    await CaBundle.path;

    expect(asked, ['exportCaBundle']);
  });

  // --- the shipped roots, for hosts whose libmpv cannot read a system store --

  /// **iOS is the case this exists for, and the claim it replaces was wrong.**
  /// The shipped iOS libmpv links mbedTLS — `Mbedtls.framework` is in the app
  /// bundle — and references Apple's Security framework zero times, so it has
  /// no system trust store to fall back on. With no `tls-ca-file` it verifies
  /// against no anchors at all and refuses an ordinary public certificate.
  test(
    'with no host handler, the shipped roots are written and used',
    () async {
      final dir = Directory.systemTemp.createTempSync('ca-roots');
      addTearDown(() => dir.deleteSync(recursive: true));
      CaBundle.cacheDirectory = dir;

      final path = await CaBundle.path;

      expect(path, isNotNull);
      expect(File(path!).readAsStringSync(), contains('BEGIN CERTIFICATE'));
      // Inside the injected directory, not beside it. The caller owns that
      // location and nothing else; a sibling is somewhere nobody cleans up and
      // nobody granted us.
      expect(dir.listSync().map((e) => e.path), [path]);
    },
  );

  /// The device's own store beats a snapshot every time: it is current and it
  /// holds the enterprise roots a bundled file cannot.
  test('a host that answers wins over the shipped roots', () async {
    final dir = Directory.systemTemp.createTempSync('ca-roots');
    addTearDown(() => dir.deleteSync(recursive: true));
    CaBundle.cacheDirectory = dir;
    answer((call) async => '/data/cache/ca.pem');

    expect(await CaBundle.path, '/data/cache/ca.pem');
    expect(dir.listSync(), isEmpty, reason: 'nothing should have been written');
  });

  /// An app update ships new roots. A cached copy from the previous version
  /// must not win, or a revoked or newly added CA never reaches the player.
  test('a stale cached copy is overwritten, not trusted', () async {
    final dir = Directory.systemTemp.createTempSync('ca-roots');
    addTearDown(() => dir.deleteSync(recursive: true));
    CaBundle.cacheDirectory = dir;

    final first = await CaBundle.path;
    File(first!).writeAsStringSync('stale rubbish');
    CaBundle.reset();

    final second = await CaBundle.path;

    expect(second, first);
    expect(File(second!).readAsStringSync(), contains('BEGIN CERTIFICATE'));
  });

  /// A trust store we cannot read is not a reason to fail the launch: the
  /// caller leaves `tls-ca-file` unset and playback refuses on its own terms,
  /// which is a message about the server rather than a crash on the way to it.
  test('an asset that will not load is null, not a throw', () async {
    final dir = Directory.systemTemp.createTempSync('ca-roots');
    addTearDown(() => dir.deleteSync(recursive: true));
    CaBundle.cacheDirectory = dir;
    CaBundle.assets = _UnreadableBundle();

    expect(await CaBundle.path, isNull);
    expect(dir.listSync(), isEmpty);
  });

  /// Handing mpv a path to an empty file is worse than handing it none:
  /// `tls-verify` would then trust nothing at all, which is the failure this
  /// class exists to prevent.
  test('an empty bundled file is treated as no roots', () async {
    final dir = Directory.systemTemp.createTempSync('ca-roots');
    addTearDown(() => dir.deleteSync(recursive: true));
    CaBundle.cacheDirectory = dir;
    CaBundle.assets = _EmptyBundle();

    expect(await CaBundle.path, isNull);
    expect(dir.listSync(), isEmpty);
  });
}

/// An asset bundle with nothing in it — a build that shipped without the roots.
final class _UnreadableBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async => throw Exception('no such asset');

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      throw Exception('no such asset');
}

/// An asset bundle whose roots file is present and empty.
final class _EmptyBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
}
