import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/category_tree_page.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/browse/library_shell.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/browse/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/shell_harness.dart';

/// The three tabs, and what a cold start costs.
///
/// Nothing in `test/browse/` can prove any of it: each of those suites builds
/// one screen on its own, and every claim here is about what happens *between*
/// them. The reload — what a route that WROTE does on its way back — is
/// `library_shell_reload_test.dart`, split off at M6.R when this file crossed
/// `file-size`'s soft warning.
void main() {
  late FakeLibraryApi api;

  const film = shellFilm;

  setUp(() {
    resetImageCache();
    api = shellApi();
  });

  Future<void> show(
    WidgetTester tester, {
    VoidCallback? onSettings,
    Size surface = const Size(800, 1400),
  }) => showShell(tester, api, onSettings: onSettings, surface: surface);

  Future<void> tab(WidgetTester tester, String label) =>
      selectTab(tester, label);

  testWidgets('a cold start issues ONE request, and it is the home rows', (
    tester,
  ) async {
    // NF1. `IndexedStack` and `TabBarView` both build every child immediately,
    // so either would have made a launch fetch the home rows, the category
    // list and an empty search at once — over someone's cellular connection,
    // for two screens they may never open.
    await show(tester);

    expect(api.calls, ['home']);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(CategoryTreePage), findsNothing);
    expect(find.byType(SearchPage), findsNothing);
  });

  testWidgets('the Library tab is built, and fetched, on first selection', (
    tester,
  ) async {
    await show(tester);

    await tab(tester, 'Library');

    expect(api.calls, ['home', 'categories']);
    expect(find.text('Films'), findsOneWidget);
  });

  testWidgets('coming back to a tab does not refetch it', (tester) async {
    // The other half of laziness: a built tab keeps its state and its scroll
    // position, so switching is free rather than a fresh download each way.
    await show(tester);
    await tab(tester, 'Library');

    await tab(tester, 'Home');
    await tab(tester, 'Library');
    await tab(tester, 'Home');

    expect(api.calls.where((c) => c == 'home'), hasLength(1));
    expect(api.calls.where((c) => c == 'categories'), hasLength(1));
  });

  testWidgets('the Search tab costs no request when it is opened', (
    tester,
  ) async {
    await show(tester);

    await tab(tester, 'Search');

    expect(api.calls, ['home']);
    expect(find.text('Type to search anything.'), findsOneWidget);
  });

  testWidgets('the navigation bar highlights the tab you are ON', (
    tester,
  ) async {
    // `selectedIndex: _tab.index` → `0` was green across the whole suite
    // (M6.R/P2.7): the user is on Search and the bar says Home. Every case
    // above asserts what is *drawn*, and the bar's own selection is the one
    // piece of state no drawn tab can speak for.
    await show(tester);
    NavigationBar bar() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    expect(bar().selectedIndex, LibraryTab.home.index);

    await tab(tester, 'Search');
    expect(bar().selectedIndex, LibraryTab.search.index);

    await tab(tester, 'Library');
    expect(bar().selectedIndex, LibraryTab.library.index);
  });

  testWidgets('Search REMEMBERS its box, its scope and its results', (
    tester,
  ) async {
    // `search_page.dart` and STATE.md both said nothing is remembered between
    // visits, and both were wrong: the tab is `Offstage`, not rebuilt, so all
    // three survive a round trip — which is what `library_shell.dart`'s own doc
    // comment claims two files away. The behaviour is the better one, so M6.R
    // fixed the documents and pinned it here rather than the other way round.
    api.searchResult = const [film];
    await show(tester);
    await tab(tester, 'Search');
    await tester.enterText(find.byType(TextField), 'movie');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<SearchField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Director').last);
    await tester.pumpAndSettle();
    expect(api.calls, contains('search(movie, director)'));

    await tab(tester, 'Home');
    await tab(tester, 'Search');

    expect(find.widgetWithText(TextField, 'movie'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<SearchField>>(
            find.byType(DropdownButton<SearchField>),
          )
          .value,
      SearchField.director,
    );
    expect(find.text('Direct Play Movie'), findsWidgets);
    // And it costs nothing to come back: the tab was not rebuilt, so no second
    // request went out for the query that is still on screen.
    expect(
      api.calls.where((c) => c.startsWith('search')),
      hasLength(2),
      reason: 'one for the text, one for the scope — and none for the return',
    );
  });

  testWidgets('an offstage tab is not on screen and not findable', (
    tester,
  ) async {
    // `Offstage` rather than removal, so state survives; finders skip it, so
    // "the tree's app bar" cannot be found while Home is showing.
    await show(tester);
    await tab(tester, 'Library');
    await tab(tester, 'Home');

    expect(find.text('Films'), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsNothing);
    expect(find.byType(CategoryTreePage), findsNothing);
  });

  testWidgets('an offstage tab stops ticking, so its spinner does not spin', (
    tester,
  ) async {
    // `Offstage` stops layout and paint; it does NOT stop tickers, so a tab
    // left sitting on a `CircularProgressIndicator` would keep animating
    // forever behind the one on screen. `TickerMode` is what stops it — and it
    // is asserted here because nothing else can see it: inverting its
    // condition passed all 518 tests, which is exactly the survivor
    // `just mutants` reported.
    await show(tester);
    await tab(tester, 'Library');

    final home = tester.element(find.byType(HomePage, skipOffstage: false));
    final library = tester.element(
      find.byType(CategoryTreePage, skipOffstage: false),
    );

    expect(
      TickerMode.valuesOf(home).enabled,
      isFalse,
      reason: 'Home is offstage',
    );
    expect(
      TickerMode.valuesOf(library).enabled,
      isTrue,
      reason: 'Library is on screen',
    );
  });

  testWidgets('a rebuilt shell hands a BUILT tab its new arguments', (
    tester,
  ) async {
    // The general case behind M6.R/P1.1. Caching each tab's widget instance
    // froze every argument it was constructed from — and `onSettings` is a
    // closure `app.dart` rebuilds around the current `SavedServer`, so the
    // Home tab kept calling the one built at sign-in and the playback settings
    // sheet reverted on every later visit.
    //
    // `title` is the visible proxy for all of them, and the second half of the
    // case is what makes the fix a fix rather than a rebuild: the Library tab
    // must take the new title WITHOUT refetching, because its state is carried
    // by the `Offstage`'s `ValueKey(tab)` rather than by a cached widget.
    final rebuild = ValueNotifier<String>('Attic NAS');
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: rebuild,
          builder: (context, title, _) => LibraryShell(api: api, title: title),
        ),
      ),
    );
    await tester.pump();
    await tab(tester, 'Library');
    expect(find.text('Attic NAS'), findsOneWidget);

    rebuild.value = 'Cellar NAS';
    await tester.pumpAndSettle();

    expect(find.text('Cellar NAS'), findsOneWidget);
    expect(find.text('Attic NAS'), findsNothing);
    expect(api.calls.where((c) => c == 'categories'), hasLength(1));
    expect(find.text('Films'), findsOneWidget);
  });

  testWidgets('a home poster opens the detail route', (tester) async {
    await show(tester);

    await tester.tap(find.text('Direct Play Movie'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaDetailPage), findsOneWidget);
    expect(api.calls, contains('mediaDetail(e4285edb34d5)'));
  });

  testWidgets('a grid poster opens the SAME detail route', (tester) async {
    // One `_openDetail` for all three tabs, so the reload below cannot depend
    // on which one the item was opened from.
    await show(tester);
    await tab(tester, 'Library');
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Direct Play Movie').first);
    await tester.pumpAndSettle();

    expect(find.byType(MediaDetailPage), findsOneWidget);
  });

  testWidgets('the settings sheet is reachable from the landing tab', (
    tester,
  ) async {
    var opened = 0;
    await show(tester, onSettings: () => opened++);

    await tester.tap(find.byTooltip('Playback settings'));

    expect(opened, 1);
  });

  testWidgets('the three destinations are named and legal tap targets', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, surface: const Size(390, 844));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    handle.dispose();
  });
}
