import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/servers/sign_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fakes.dart';

/// Sign-in runs unmodified on a television — it is reached before `TvShell`
/// ever mounts — so a remote has to reach every control on it the same way
/// M8's rail walk proved it had to reach the shell's. The mode toggle is new
/// with this milestone and gets the same proof rather than an assumption.
///
/// **Not proven here: that `Password`/`Username`/`Sign in` are individually
/// reachable in the same walk.** `docs/field-notes.md` records why — a
/// `TextField`'s focus context sits below its label, so two adjacent
/// unlabelled fields collide in `dpadReachable`'s label-keyed set and the
/// walk stops early, a limitation that predates this file (Username and
/// Password were already unlabelled) rather than something the toggle
/// introduced.
void main() {
  final server = SavedServer(
    id: const ServerId('http://nas.local:8099'),
    name: 'nas.local',
    baseUrl: Uri.parse('http://nas.local:8099'),
  );

  Future<void> show(WidgetTester tester, {SavedServer? saved}) => pumpTv(
    tester,
    FileFinScope(
      dependencies: AppDependencies(
        secrets: InMemorySecretStore(),
        network: FakeNetworkStatus(),
        playbackHostFactory: fakeHostFactory(),
        nowPlayingFactory: fakeNowPlayingFactory(),
        settings: SettingsStore(
          Directory.systemTemp.createTempSync('filefin-signin-tv-'),
        ),
        apiFactory: (_, {pin}) => FakeLibraryApi(),
      ),
      child: SignInPage(server: saved ?? server, onSignedIn: (_, _) {}),
    ),
  );

  testWidgets('both mode segments are reachable by D-pad', (tester) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    expect(reached, contains('Password'));
    expect(reached, contains('Access token'));
  });

  testWidgets('the centre button switches segments, not just a tap', (
    tester,
  ) async {
    await show(tester);

    await dpadActivate(tester, 'Access token');

    expect(
      find.widgetWithText(TextField, 'Personal access token'),
      findsOneWidget,
    );
  });

  testWidgets(
    'from the token-mode start, the walk reaches Sign in past one '
    'unlabelled field',
    (tester) async {
      // Token mode has exactly one text field between the toggle and the
      // button, so — unlike password mode's two adjacent ones — nothing
      // collides in the walk's label set, and this is the honest proof
      // Phase 5 asks for: the new field does not trap focus behind it.
      await show(tester, saved: server.withTokenAuth());

      final reached = await dpadReachable(tester);

      expect(reached, contains('Password'));
      expect(reached, contains('Access token'));
      expect(reached, contains('Sign in'));
    },
  );
}
