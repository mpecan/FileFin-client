import 'package:filefin_mobile/src/playback/ca_bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The device trust store libmpv cannot read for itself.
///
/// **Every arm here was shipped untested until the redesign**, because
/// `CaBundle.path` opened with `if (!Platform.isAndroid) return null` and the
/// runner reports macOS: the export, its missing-handler arm and the
/// empty-string rule were unreachable from any test on this host. The guard is
/// gone and bought nothing — a host without the handler answers
/// `MissingPluginException`, which is what the export already catches.
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

  /// iOS, desktop, and the runner: the system libmpv uses the OS trust store
  /// natively there and no bundle is needed.
  test('a host with no handler is not an error, it is null', () async {
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
}
