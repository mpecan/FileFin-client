import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/ui_state.dart';
import 'package:filefin_mobile/src/browse/search_controller.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// The debounce, the supersede, and the request that is never made.
///
/// `testWidgets` rather than `test`, and not because there is a widget here:
/// its body runs under `FakeAsync`, so `tester.pump(Duration)` advances the
/// clock exactly and the 300 ms boundary can be asserted on **both** sides
/// without the suite waiting a real third of a second per case.
///
/// It also buys the free gate: `flutter_test` fails a test that ends with a
/// timer still pending, so a `dispose` that forgot to cancel one cannot pass.
///
/// **Every pump below carries a duration, including the ones that look like
/// they need not.** A bare `tester.pump()` flushes microtasks and does *not*
/// advance the fake clock, so a `Timer(Duration.zero)` never fires under it —
/// four of these cases failed with an empty call list until the 1 ms was
/// added, which looks exactly like a controller that never issued a request.
void main() {
  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi()..searchResult = const <MediaSummary>[];
  });

  const found = [MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Ada')];

  Future<MediaSearchController> controller(
    WidgetTester tester, {
    Duration? debounce,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Nothing is passed when a case wants the SHIPPED debounce: the 299/301
    // boundary below is the only thing that exercises the class's own default,
    // and a helper that re-stated 300 ms would have left that constant
    // untested.
    final c = debounce == null
        ? MediaSearchController(api: api)
        : MediaSearchController(api: api, debounce: debounce);
    addTearDown(c.dispose);
    return c;
  }

  List<String> searches() =>
      api.calls.where((c) => c.startsWith('search')).toList();

  testWidgets('typing a word is ONE request, carrying the final text', (
    tester,
  ) async {
    // Twelve keystrokes at 40 ms — a person typing — must not be twelve
    // requests. `docs/verification-backlog.md` row F is the same measurement
    // on a real device, which has not been made.
    final search = await controller(tester);

    for (final text in ['k', 'ku', 'kur', 'kuro', 'kuros', 'kurosawa']) {
      search.setText(text);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(searches(), ['search(kurosawa, all)']);
  });

  testWidgets('299 ms is not enough and 301 ms is — both sides of it', (
    tester,
  ) async {
    final search = await controller(tester);

    search.setText('ada');
    await tester.pump(const Duration(milliseconds: 299));
    expect(searches(), isEmpty, reason: 'still inside the debounce');

    await tester.pump(const Duration(milliseconds: 2));

    expect(searches(), ['search(ada, all)']);
  });

  testWidgets('a superseding query CANCELS the first request', (tester) async {
    // Two in-flight requests can finish in either order, so an older one
    // landing last would overwrite the newer answer and nothing on screen
    // would say so. `AsyncController.load` cancels; this proves it happens.
    final search = await controller(tester, debounce: Duration.zero);

    search.setText('ada');
    await tester.pump(const Duration(milliseconds: 1));
    search.setText('grace');
    await tester.pump(const Duration(milliseconds: 1));

    expect(searches(), ['search(ada, all)', 'search(grace, all)']);
    expect(api.tokens.first!.isCancelled, isTrue);
    expect(api.tokens.last!.isCancelled, isFalse);
  });

  testWidgets('the TRIMMED text is what reaches the wire', (tester) async {
    // `SearchQuery.wireText` trims and `search_query_test.dart` proves the
    // getter does; nothing proved the CALLER uses it. Rewriting
    // `asked.wireText` to `asked.text` in `_fetch` was green across the whole
    // suite (M6.R/P2.4) — and it is not cosmetic: the nine text scopes do not
    // `TrimSpace` server-side (`db/search.go:52`), so `"  ada  "` on the wire
    // searches titles for a string with spaces in it and finds nothing, while
    // the caption on screen quotes the trimmed `ada`. The user is told there
    // are no matches for a query that was never sent.
    //
    // `mutation_test` cannot generate this mutant — it substitutes operators,
    // not identifiers — so a test is the only thing that can close it.
    final search = await controller(tester, debounce: Duration.zero);

    search.setText('  ada  ');
    await tester.pump(const Duration(milliseconds: 1));

    expect(searches(), ['search(ada, all)']);
  });

  testWidgets('a blank query issues NO request at all', (tester) async {
    final search = await controller(tester, debounce: Duration.zero);

    search.setText('   ');
    await tester.pump(const Duration(milliseconds: 1));

    expect(searches(), isEmpty);
    expect(api.calls, isEmpty);
  });

  testWidgets('clearing the box mid-search cancels the search it clears', (
    tester,
  ) async {
    // The reason the blank case goes through `load()` rather than skipping it:
    // the request that is already out has to be abandoned, or its answer lands
    // under an empty box.
    final search = await controller(tester, debounce: Duration.zero);
    search.setText('ada');
    await tester.pump(const Duration(milliseconds: 1));

    search.setText('');
    await tester.pump(const Duration(milliseconds: 1));

    expect(searches(), ['search(ada, all)']);
    expect(api.tokens.single!.isCancelled, isTrue);
  });

  testWidgets('the blank outcome is DATA, not a spinner', (tester) async {
    final search = await controller(tester, debounce: Duration.zero);

    await search.start();

    expect(search.results.state, isA<UiData<SearchOutcome>>());
    expect(api.calls, isEmpty);
  });

  testWidgets('the FIELD reaches the wire, not just the text', (tester) async {
    // An unrecognised `field` degrades to `all` upstream (`db/search.go:70`),
    // so a screen that dropped the scope still returns plausible results and
    // quietly ignores what the user picked. `search(Kurosawa, director)`,
    // never `search(Kurosawa, all)`.
    final search = await controller(tester, debounce: Duration.zero);

    search
      ..setText('Kurosawa')
      ..setField(SearchField.director);
    await tester.pump(const Duration(milliseconds: 1));

    expect(searches().last, 'search(Kurosawa, director)');
  });

  testWidgets('a scope change is IMMEDIATE, and fires exactly one request', (
    tester,
  ) async {
    // Immediate because picking a scope is deliberate. Exactly one, because
    // the pending keystroke timer has to be cancelled or it fires a second
    // identical load a moment later.
    final search = await controller(tester);
    search.setText('ada');
    await tester.pump(const Duration(milliseconds: 100));

    search.setField(SearchField.tag);
    await tester.pump(const Duration(milliseconds: 1));
    expect(searches(), ['search(ada, tag)']);

    await tester.pump(const Duration(milliseconds: 500));

    expect(searches(), ['search(ada, tag)']);
  });

  testWidgets('an unparseable year is refused before the socket', (
    tester,
  ) async {
    // `field=year&q=nineteen` would come back `200 []` — the numeric scopes
    // fail closed (M6.0/E-4) — so the request buys nothing and the screen can
    // say why instead of showing an empty library.
    final search = await controller(tester, debounce: Duration.zero);

    search
      ..setField(SearchField.year)
      ..setText('nineteen');
    await tester.pump(const Duration(milliseconds: 1));

    expect(api.calls, isEmpty);
    final state = search.results.state as UiData<SearchOutcome>;
    expect(state.value.results, isEmpty);
    expect(state.value.query.field, SearchField.year);
  });

  testWidgets('a parseable year DOES reach the socket — the other side', (
    tester,
  ) async {
    final search = await controller(tester, debounce: Duration.zero);

    search
      ..setField(SearchField.year)
      ..setText('1994');
    await tester.pump(const Duration(milliseconds: 1));

    expect(searches(), ['search(1994, year)']);
  });

  testWidgets('the outcome carries the query it answers', (tester) async {
    // So a caption can never name a query nobody ran.
    api.searchResult = found;
    final search = await controller(tester, debounce: Duration.zero);

    search.setText('ada');
    await tester.pump(const Duration(milliseconds: 1));

    final state = search.results.state as UiData<SearchOutcome>;
    expect(state.value.query.text, 'ada');
    expect(state.value.results, found);
  });

  testWidgets('a failure is a failure, not an empty result', (tester) async {
    api.searchResult = CacheUnavailable(Uri.parse('http://nas/api'));
    final search = await controller(tester, debounce: Duration.zero);

    search.setText('ada');
    await tester.pump(const Duration(milliseconds: 1));

    expect(search.results.state, isA<UiFailure<SearchOutcome>>());
  });

  testWidgets('the query is readable while it is still being typed', (
    tester,
  ) async {
    // The picker draws from it, so it must move on the keystroke rather than
    // on the request 300 ms later.
    final search = await controller(tester);
    var notified = 0;
    search
      ..addListener(() => notified++)
      ..setText('ad');

    expect(search.query.text, 'ad');
    expect(notified, 1);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('dispose cancels the pending keystroke and the request', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final search = MediaSearchController(api: api)..setText('ada');
    await tester.pump(const Duration(milliseconds: 100));

    search.dispose();
    await tester.pump(const Duration(milliseconds: 500));

    // No request went out, and — the half `flutter_test` gates for free — the
    // test ends with no pending timer.
    expect(api.calls, isEmpty);
  });
}
