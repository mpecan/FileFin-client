import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What this file can and cannot prove, said once so nobody reads more into it.
///
/// It proves that a key someone might delete is still in the file. It cannot
/// prove that a socket opens: whether cleartext `http://` actually connects,
/// whether ATS lets a request through to `192.168.x.x`, and whether the iOS 14+
/// local-network prompt appears and is survivable are all OS-enforced and need
/// a device. `docs/verification-backlog.md` carries each of those with the
/// experiment that would settle it.
///
/// The other half of the evidence is not here at all: `flutter build apk
/// --debug` and `flutter build ios --no-codesign` were run at M3.1 and are
/// recorded in STATE.md. Those prove the manifest MERGES and the plist PARSES,
/// which content assertions on their own cannot.
void main() {
  group('Android', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    final config = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    );
    final gradle = File('android/app/build.gradle.kts');

    test('the manifest asks for INTERNET', () {
      expect(
        manifest.readAsStringSync(),
        contains('android.permission.INTERNET'),
      );
    });

    test('the manifest permits cleartext and names the security config', () {
      final text = manifest.readAsStringSync();
      expect(text, contains('android:usesCleartextTraffic="true"'));
      expect(
        text,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
    });

    test('the security config permits cleartext at BASE scope', () {
      // Base scope rather than a domain list is forced: a saved server is any
      // host the user types, so there is no domain to enumerate. A
      // domain-scoped config would pass a naive grep and permit nothing.
      final text = config.readAsStringSync();
      expect(text, contains('<base-config cleartextTrafficPermitted="true">'));
      expect(text, isNot(contains('<domain-config')));
    });

    test('the security config re-states the system trust anchors', () {
      // A base-config with no trust-anchors REPLACES the platform default
      // rather than extending it, and the app would then trust nothing over
      // TLS at all — F15's failure mode dressed as a config typo.
      final text = config.readAsStringSync();
      expect(text, contains('<certificates src="system" />'));
    });

    test('minSdk is 26 as a literal, not flutter.minSdkVersion (C5)', () {
      // `flutter.minSdkVersion` is 24 on this SDK. A floor that moves when
      // Flutter moves is not a constraint, and C5 is decision D7.
      final text = gradle.readAsStringSync();
      expect(text, contains('minSdk = 26'));
      expect(text, isNot(contains('minSdk = flutter.minSdkVersion')));
    });
  });

  group('iOS', () {
    final plist = File('ios/Runner/Info.plist');
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');

    test('ATS allows local networking', () {
      final text = plist.readAsStringSync();
      expect(text, contains('<key>NSAppTransportSecurity</key>'));
      expect(text, contains('<key>NSAllowsLocalNetworking</key>'));
    });

    test('ATS does NOT allow arbitrary loads', () {
      // The larger grant would relax ATS for every host on the internet.
      // Deleting NSAllowsLocalNetworking and reaching for it instead is the
      // tempting "fix" when a public plain-http server is refused.
      //
      // The assertion is on the KEY MARKUP, not on the bare word, and the
      // first version was not: the plist's own comment explaining why the
      // grant is absent contains the word, so `isNot(contains('NSAllows…'))`
      // failed on a correct file. A check a comment can satisfy — or break —
      // is the shape CLAUDE.md names under "an assertion satisfiable in
      // prose"; only a `<key>` element is a setting.
      expect(
        plist.readAsStringSync(),
        isNot(contains('<key>NSAllowsArbitraryLoads</key>')),
      );
    });

    test('a local-network usage description exists and says something', () {
      // iOS 14+ prompts before the first local-network connection and KILLS an
      // app with no string to show. An empty string is the same as none.
      final text = plist.readAsStringSync();
      final match = RegExp(
        r'<key>NSLocalNetworkUsageDescription</key>\s*<string>([^<]*)</string>',
      ).firstMatch(text);
      expect(match, isNotNull);
      expect(match!.group(1)!.trim().length, greaterThan(20));
    });

    test('the deployment target is 15.0 everywhere (C5)', () {
      // Every build configuration, not just one: Xcode writes three, and a
      // Release configuration left at 13.0 is a floor nobody notices until a
      // TestFlight build installs on a device that cannot run it.
      final targets = RegExp(
        'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
      ).allMatches(pbxproj.readAsStringSync()).map((m) => m.group(1)).toList();
      expect(targets, isNotEmpty);
      expect(targets, everyElement('15.0'));
    });
  });
}
