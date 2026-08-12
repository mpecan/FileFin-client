import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/tv/tv_home_page.dart';
import 'package:filefin_mobile/src/tv/tv_library_page.dart';
import 'package:filefin_mobile/src/tv/tv_search_page.dart';
import 'package:filefin_mobile/src/tv/tv_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fakes.dart';

/// The television's shell: which pane is built, when, and whether a remote can
/// get between the rail and the pane beside it.
void main() {
  const film = MediaSummary(id: MediaId('e4285edb34d5'), title: 'Woodstock');

  late FakeLibraryApi api;

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()
      ..posterResult = null
      ..homeResult = const HomeRows(continueRow: [film])
      ..searchResult = const <MediaSummary>[]
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
      ]
      ..categoryMediaResult = const [film];
  });

  Future<List<String>> show(WidgetTester tester) async {
    final opened = <String>[];
    await pumpTv(
      tester,
      TvShell(
        api: api,
        title: 'Attic NAS',
        onSettings: () => opened.add('settings'),
      ),
    );
    return opened;
  }

  /// NF1: a cold start issues ONE request. The library's categories and the
  /// blank search are two more, and neither is anything a user asked for.
  testWidgets('only the landing pane is built, so only it fetches', (
    tester,
  ) async {
    await show(tester);

    expect(find.byType(TvHomePage), findsOneWidget);
    expect(find.byType(TvLibraryPage), findsNothing);
    expect(find.byType(TvSearchPage), findsNothing);
    expect(api.calls, ['home']);
  });

  testWidgets('choosing Library with the remote builds it, once', (
    tester,
  ) async {
    await show(tester);

    await dpadActivate(tester, 'Library');
    await tester.pumpAndSettle();

    expect(find.byType(TvLibraryPage), findsOneWidget);
    expect(api.calls, ['home', 'categories']);

    // Back to Home and out again: the pane stays built, so nothing is asked
    // for a second time.
    await dpadActivate(tester, 'Home');
    await tester.pumpAndSettle();
    await dpadActivate(tester, 'Library');
    await tester.pumpAndSettle();

    expect(api.calls, ['home', 'categories']);
  });

  /// Settings is a sheet rather than a pane, so the rail must not move to it —
  /// a fourth destination holding one sheet would be a screen with nothing on
  /// it, and a rail marking it as "where you are" would be lying.
  testWidgets('Settings opens the sheet and leaves the rail where it was', (
    tester,
  ) async {
    final opened = await show(tester);

    await dpadActivate(tester, 'Settings');
    await tester.pumpAndSettle();

    expect(opened, ['settings']);
    expect(find.byType(TvHomePage), findsOneWidget);
  });

  /// The whole reason the rail's `FocusScope` had to go: a user who moves onto
  /// the navigation has to be able to move back off it. Asserted as a round
  /// trip rather than as one hop, because entering was never the broken half.
  testWidgets('focus moves off the rail into the pane and back again', (
    tester,
  ) async {
    await show(tester);

    await dpadFocus(tester, 'Woodstock');
    expect(focusedLabel(tester), 'Woodstock');

    await dpadFocus(tester, 'Home');
    expect(focusedLabel(tester), 'Home');
  });

  /// The one detail route, and the one place the home rows are reloaded: a
  /// write anywhere re-stamps `updated`, which orders all three home buckets
  /// (M6.0/E-3), so the rows cannot be predicted and are refetched instead.
  testWidgets('opening an item and writing on it reloads the rows', (
    tester,
  ) async {
    api.mediaDetailResult = const MediaDetail(id: MediaId('e4285edb34d5'));
    await show(tester);
    expect(api.calls.where((c) => c == 'home'), hasLength(1));

    await dpadActivate(tester, 'Open');
    await tester.pumpAndSettle();
    expect(find.byType(MediaDetailPage), findsOneWidget);

    await tester.tap(find.byTooltip('Mark watched'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'home'), hasLength(2));
  });

  /// The other half: a visit that wrote NOTHING must not pay for a refetch.
  testWidgets('closing an item without writing reloads nothing', (
    tester,
  ) async {
    api.mediaDetailResult = const MediaDetail(id: MediaId('e4285edb34d5'));
    await show(tester);

    await dpadActivate(tester, 'Open');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'home'), hasLength(1));
  });

  testWidgets('every destination and the hero are reachable by D-pad', (
    tester,
  ) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    expect(
      reached,
      containsAll(['Home', 'Library', 'Search', 'Settings', 'Open']),
    );
  });

  testWidgets('choosing Search builds the search pane, and only then', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(TvSearchPage), findsNothing);

    await dpadActivate(tester, 'Search');
    await tester.pumpAndSettle();

    expect(find.byType(TvSearchPage), findsOneWidget);
    // A blank query asks the server nothing, so the pane costs one build and
    // no request.
    expect(api.calls, ['home']);
  });
}
