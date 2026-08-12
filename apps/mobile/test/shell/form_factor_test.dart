import 'package:filefin_mobile/src/shell/form_factor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one question that decides which of the two shells a launch builds.
///
/// **Every arm is reachable from a host test, and that is why the probe does
/// not gate on `Platform.isAndroid`.** A `Platform` guard would make the
/// television arm dead code under `flutter test` — the runner reports macOS —
/// so the branch that matters most could never be exercised. A device that has
/// no handler for the channel answers `MissingPluginException`, which is
/// exactly what iOS and desktop do, so the guard buys nothing the absent
/// handler does not already give.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?>? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(formFactorChannel, handler);
    addTearDown(
      () => messenger.setMockMethodCallHandler(formFactorChannel, null),
    );
  }

  test('a device that says it is a television gets the TV shell', () async {
    final asked = <String>[];
    answer((call) async {
      asked.add(call.method);
      return true;
    });
    expect(await detectFormFactor(), FormFactor.tv);
    expect(asked, ['isTelevision']);
  });

  test('a device that says it is not gets the phone shell', () async {
    answer((call) async => false);
    expect(await detectFormFactor(), FormFactor.phone);
  });

  /// iOS and desktop, which register no handler at all.
  test('no handler for the channel is a phone', () async {
    expect(await detectFormFactor(), FormFactor.phone);
  });

  /// A host that answers but fails. Falling back to the phone shell is the
  /// safe half: a phone layout on a television is usable with a remote,
  /// whereas a TV layout on a phone is unreadable and has no touch targets.
  test('a host that throws is a phone', () async {
    answer((call) async => throw PlatformException(code: 'unavailable'));
    expect(await detectFormFactor(), FormFactor.phone);
  });

  /// A handler that answers `null` — the shape a stub returns before anyone
  /// has written the Kotlin. It must not be read as "yes".
  test('a null answer is a phone', () async {
    answer((call) async => null);
    expect(await detectFormFactor(), FormFactor.phone);
  });
}
