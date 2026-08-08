import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  final deps = AppDependencies(
    secrets: InMemorySecretStore(),
    settings: SettingsStore(Directory.systemTemp),
    apiFactory: (_) => FakeLibraryApi(),
  );

  testWidgets('a screen under the scope reads the dependencies', (
    tester,
  ) async {
    late AppDependencies seen;
    await tester.pumpWidget(
      FileFinScope(
        dependencies: deps,
        child: Builder(
          builder: (context) {
            seen = FileFinScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(identical(seen, deps), isTrue);
  });

  testWidgets('a screen with no scope above it says so', (tester) async {
    // A nullable `of` would push the same `!` to every call site and turn a
    // wiring mistake into a null dereference three frames away.
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(
            () => FileFinScope.of(context),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('No FileFinScope'),
              ),
            ),
          );
          return const SizedBox();
        },
      ),
    );
  });

  test('updateShouldNotify is identity-based, not structural', () {
    // Measured directly rather than through a rebuild count: rebuilding a
    // widget test's tree replaces the child widgets too, so a counter would
    // rise whether or not the scope notified — the test would pass over a
    // broken `updateShouldNotify` and prove nothing.
    const child = SizedBox();
    final same = FileFinScope(dependencies: deps, child: child);
    final other = FileFinScope(
      dependencies: AppDependencies(
        secrets: deps.secrets,
        settings: deps.settings,
        apiFactory: deps.apiFactory,
      ),
      child: child,
    );

    expect(same.updateShouldNotify(same), isFalse);
    expect(other.updateShouldNotify(same), isTrue);
  });
}
