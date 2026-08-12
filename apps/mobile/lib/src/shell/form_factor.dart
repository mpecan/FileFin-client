import 'package:flutter/services.dart';

/// Which of the two shells a launch builds.
///
/// Two members rather than a size breakpoint, because the difference is the
/// **input device** and not the pixel count. A 10-inch tablet is a phone here:
/// it has a finger on the glass, so it gets thumb-reachable targets and a
/// bottom bar. A 55-inch television two metres away is not a very large
/// tablet — it has a D-pad, no pointer, and text has to survive being read
/// from a sofa.
enum FormFactor {
  /// Android and iOS handsets and tablets: the `1a` screens.
  phone,

  /// Android TV and Google TV: the `1b` rail-and-rows screens.
  tv,
}

/// The channel `MainActivity` answers `isTelevision` on.
///
/// Public so its own suite can mock it; nothing outside this library invokes
/// it (§5, `public_member_no_consumer`).
const formFactorChannel = MethodChannel(
  'dev.filefin.filefin_mobile/form_factor',
);

/// Asks the host whether it is a television, once, at launch.
///
/// **It deliberately does not gate on `Platform.isAndroid`.** A platform guard
/// would make [FormFactor.tv] unreachable under `flutter test`, which reports
/// macOS, and a branch no test can enter is a branch nothing verifies. Every
/// host without the handler — iOS, desktop, and the test runner itself —
/// answers `MissingPluginException`, so the guard would only duplicate an
/// answer the absent handler already gives.
///
/// **Every failure lands on [FormFactor.phone], and the asymmetry is the
/// point.** A phone layout on a television is navigable with a remote; a TV
/// layout on a phone has no target under 44 points and no bottom bar.
Future<FormFactor> detectFormFactor() async {
  try {
    final isTv = await formFactorChannel.invokeMethod<bool>('isTelevision');
    return (isTv ?? false) ? FormFactor.tv : FormFactor.phone;
  } on PlatformException {
    return FormFactor.phone;
  } on MissingPluginException {
    return FormFactor.phone;
  }
}
