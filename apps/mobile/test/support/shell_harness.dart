import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/library_shell.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// The shared setup for the two `LibraryShell` suites.
///
/// It exists because `file-size`'s 400-line soft warning may fall or hold and
/// never rise, and `library_shell_test.dart` crossed it at M6.R: the tabs and
/// the reload are two subjects and they are now two files. Extracting the
/// harness rather than copying it keeps `just dupes` honest and, more usefully,
/// keeps one description of what a seeded shell contains.
const shellFilm = MediaSummary(
  id: MediaId('e4285edb34d5'),
  title: 'Direct Play Movie',
);

/// A fake seeded so every tab has something to draw: one home row, one
/// category, one item in it, and a detail for that item.
FakeLibraryApi shellApi() => FakeLibraryApi()
  ..posterResult = null
  ..homeResult = const HomeRows(continueRow: [shellFilm])
  ..searchResult = const <MediaSummary>[]
  ..categoriesResult = const [
    Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
  ]
  ..categoryMediaResult = const [shellFilm]
  ..mediaDetailResult = const MediaDetail(
    id: MediaId('e4285edb34d5'),
    title: 'Direct Play Movie',
    year: 2020,
  );

/// Pumps a shell over [api].
///
/// [outcome] is what a player route would pop; passing it is also what makes
/// `onPlay` non-null, and therefore what makes the Play button exist at all.
Future<void> showShell(
  WidgetTester tester,
  FakeLibraryApi api, {
  VoidCallback? onSettings,
  PlaybackOutcome? outcome,
  Size surface = const Size(800, 1400),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryShell(
        api: api,
        title: 'Attic NAS',
        onSettings: onSettings,
        onPlay: outcome == null ? null : (_, _, _) async => outcome,
      ),
    ),
  );
  await tester.pump();
}

/// Taps a destination in the navigation bar and settles.
Future<void> selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Clears the image cache between cases, so a poster from one does not satisfy
/// the next.
void resetImageCache() => PaintingBinding.instance.imageCache
  ..clear()
  ..clearLiveImages();
