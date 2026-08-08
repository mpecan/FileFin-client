@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/category_grid_page.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// NF2's evidence, and precisely what it is evidence OF.
///
/// **60fps cannot be measured here, structurally.** `flutter test` runs
/// `flutter_tester` under `AutomatedTestWidgetsFlutterBinding`: a fake clock,
/// frames pumped on demand, no vsync, no rasterizer and fabricated
/// `FrameTiming`. The real instrument is `flutter drive` +
/// `package:integration_test` + `TimelineSummary`, and `flutter_tools` demands
/// a connected device for anything under `integration_test/`. That is a
/// measured fact, and `docs/verification-backlog.md` row 1 carries the exact
/// experiment.
///
/// What IS measurable here is the property 60fps rests on: per-frame build and
/// layout cost O(visible), not O(5000). A regression that breaks it — a
/// `Column` wrapper, a `.toList()` per build, keep-alives left on — breaks
/// these tests. The invariants are gated; the timing number at the bottom is
/// reported and deliberately not.
///
/// **Where the 5000 items come from, and why it is arranged this way.** They
/// are decoded ONCE in `setUpAll`, by the real `FileFinClient` over a real
/// `dart:io` `HttpServer` — so what the grid renders is 5000 payloads that
/// crossed a socket and went through the real decoder, not 5000 literals we
/// wrote ourselves (§8's reasoning, applied to a shape rather than a field).
///
/// The widget bodies then use an injected port over those same objects, and
/// that is forced rather than preferred. A `testWidgets` body runs under
/// `FakeAsync`: a request *initiated* there registers its timers in the fake
/// zone and never completes, whatever `runAsync` does later — `runAsync` makes
/// real time pass, it does not retroactively move a pending socket into the
/// real zone. The first draft of this file pumped the page and waited two real
/// seconds for tiles that could never arrive. `setUpAll` runs outside
/// `FakeAsync`, which is why the real half lives there.
void main() {
  const itemCount = 5000;
  const category = Category(id: CategoryId(1), leaf: 'Films', name: 'Films');

  late List<MediaSummary> realItems;

  setUpAll(() async {
    // `flutter_test`'s binding installs an HttpOverrides that answers 400 for
    // everything (measured at M3.0). Real sockets are what make the payloads
    // below real.
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final response = request.response
          ..headers.contentType = ContentType('application', 'json')
          ..write(
            jsonEncode([
              for (var i = 0; i < itemCount; i++)
                {
                  'id': i.toRadixString(16).padLeft(12, '0'),
                  'title': 'Item $i',
                  'year': 2000 + i % 20,
                  'hasPoster': true,
                },
            ]),
          );
        await response.close();
      }),
    );
    final api = FileFinLibraryApi(
      FileFinClient.forServer(
        server: const ServerId('big'),
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        secrets: InMemorySecretStore(),
      ),
    );
    realItems = await api.categoryMedia(const CategoryId(1));
    api.close();
    await server.close(force: true);
  });

  test('the real client decodes $itemCount items off a real socket', () {
    // The contract half, in a plain `test()` because there is no widget in it.
    expect(realItems, hasLength(itemCount));
    expect(realItems.first.id.value, '000000000000');
    expect(realItems.last.title, 'Item ${itemCount - 1}');
    expect(realItems.every((i) => i.hasPoster), isTrue);
  });

  group('the placeholder gate', () {
    // The four cases of `Image`'s frameBuilder contract. Inline this condition
    // was unreachable from a widget test — a real decode is engine-side async
    // that a `testWidgets` body's fake clock does not drive — and `just
    // mutants` duly rewrote it two ways with the suite green. Both rewrites
    // are a tile that covers a poster it already has.
    test('nothing decoded yet, and not from the cache: still loading', () {
      expect(posterStillLoading(null, wasSync: false), isTrue);
    });

    test('a frame has arrived: not loading', () {
      expect(posterStillLoading(0, wasSync: false), isFalse);
    });

    test('already in the ImageCache on the first build: not loading', () {
      // `wasSync` is the cache hit. Treating it as loading would flash a
      // placeholder over a poster that was available immediately — which is
      // every tile scrolled back to.
      expect(posterStillLoading(null, wasSync: true), isFalse);
    });

    test('a later frame of a cached image: not loading', () {
      expect(posterStillLoading(1, wasSync: true), isFalse);
    });
  });

  group('the grid, over those decoded items', () {
    late FakeLibraryApi api;

    setUp(() {
      // Flutter's `ImageCache` is global and survives between tests, and
      // `PosterImageProvider` keys on (ServerId, MediaId, PosterSize) — so a
      // poster fetched by an earlier test is served from the cache here and no
      // request is made at all. That dedup is the point of the provider; it
      // also means a test that counts requests has to start from an empty
      // cache. Measured: "posters are lazy" passed alone and failed in the
      // suite, with zero requests.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      api = FakeLibraryApi()
        ..categoryMediaResult = realItems
        ..posterResult = null;
    });

    Future<void> pump(
      WidgetTester tester, {
      Size? surface,
      void Function(MediaSummary)? onOpen,
      List<MediaSummary>? items,
    }) async {
      if (items != null) api.categoryMediaResult = items;
      if (surface != null) {
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryGridPage(
            api: api,
            category: category,
            onOpen: onOpen ?? (_) {},
          ),
        ),
      );
      await tester.pump();
    }

    ScrollPosition positionOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    int posterCalls() =>
        api.calls.where((c) => c.startsWith('posterBytes')).length;

    testWidgets(
      '$itemCount items build a bounded number of tiles, everywhere',
      (tester) async {
        await pump(tester);
        final atTop = find.byType(PosterTile).evaluate().length;

        final position = positionOf(tester);
        position.jumpTo(position.maxScrollExtent / 2);
        await tester.pump();
        final atMiddle = find.byType(PosterTile).evaluate().length;

        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final atEnd = find.byType(PosterTile).evaluate().length;

        expect(atTop, greaterThan(0));
        for (final live in [atTop, atMiddle, atEnd]) {
          expect(
            live,
            lessThan(80),
            reason: 'build and layout must be O(visible), not O($itemCount)',
          );
        }
      },
    );

    testWidgets('posters are lazy — far fewer requests than items', (
      tester,
    ) async {
      await pump(tester);
      final afterFirstFrame = posterCalls();

      final position = positionOf(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      expect(afterFirstFrame, greaterThan(0), reason: 'the visible ones fetch');
      expect(
        posterCalls(),
        lessThan(200),
        reason: 'one request per item would be $itemCount of them',
      );
    });

    testWidgets('poster requests never exceed the tiles ever built', (
      tester,
    ) async {
      // The invariant that actually bounds the work: a tile fetches at most
      // once, so the request count can never run ahead of the widget count.
      await pump(tester);
      final position = positionOf(tester);
      var built = find.byType(PosterTile).evaluate().length;
      for (var i = 0; i < 10; i++) {
        position.jumpTo(position.pixels + 600);
        await tester.pump();
        built += find.byType(PosterTile).evaluate().length;
      }

      expect(posterCalls(), lessThanOrEqualTo(built));
    });

    testWidgets('the listing is fetched ONCE for $itemCount items', (
      tester,
    ) async {
      // A rebuild that re-fetched would turn every scroll into a $itemCount
      // download, and nothing on screen would say so.
      await pump(tester);
      final position = positionOf(tester);
      for (var i = 0; i < 20; i++) {
        position.jumpTo(position.pixels + 200);
        await tester.pump();
      }

      expect(
        api.calls.where((c) => c.startsWith('categoryMedia')),
        hasLength(1),
      );
    });

    testWidgets('a tile scrolled away cancels its poster request (NF5)', (
      tester,
    ) async {
      // Without this, flinging through a large category queues every request
      // it passed and the items the user stopped on wait behind them.
      await pump(tester);
      final tokensAtTop = [...api.tokens.whereType<CancelToken>()];

      final position = positionOf(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      expect(tokensAtTop, isNotEmpty);
      expect(
        tokensAtTop.where((t) => t.isCancelled),
        isNotEmpty,
        reason: 'the tiles left behind cancelled',
      );
    });

    testWidgets('a tile is a readable size and a legal tap target', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, surface: const Size(390, 844));

      final size = tester.getSize(find.byType(PosterTile).first);

      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, lessThanOrEqualTo(160));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });

    testWidgets(
      'build + layout wall clock — REPORTED, NOT GATED; read the label',
      (tester) async {
        await pump(tester);
        final position = positionOf(tester);

        // Timed with the FAKE clock advancing between frames, because `pump`
        // cannot be called inside `runAsync`. One more reason this is not
        // frame time.
        final watch = Stopwatch()..start();
        for (var i = 0; i < 60; i++) {
          position.jumpTo(position.pixels + 40);
          await tester.pump();
        }
        final elapsed = watch.elapsed;

        // The number is the deliverable here: a human reads it in the test
        // log and notices when it moves. An expectation would make it a gate,
        // which the label above explains it must never be.
        // ignore: avoid_print
        print(
          'NF2 tripwire: ${(elapsed.inMicroseconds / 60).toStringAsFixed(0)} '
          'us/frame over 60 scrolled pumps of a $itemCount-item grid. '
          'THIS IS NOT FRAME TIME AND IS NOT EVIDENCE OF 60fps: build and '
          'layout only, debug JIT, flutter_tester, no rasterization, fake '
          'vsync. It is a number for a human to notice moving, never a '
          'threshold for a machine — a flaky timing gate in `just check` would '
          'be worse than none. Real frame timing is '
          'docs/verification-backlog.md row 1.',
        );

        expect(elapsed.inMicroseconds, greaterThan(0));
      },
    );

    testWidgets('an item with NO id gets a tile like any other', (
      tester,
    ) async {
      // `client.dart:196-199` is explicit that filtering bad items out of a
      // list IS the silent failure G5 forbids. The list renders as decoded and
      // opening the bad one fails loudly, naming the value.
      await pump(
        tester,
        items: const [
          MediaSummary(title: 'No id', year: 2020),
          MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Fine'),
        ],
      );

      expect(find.byType(PosterTile), findsNWidgets(2));
      expect(find.text('No id'), findsOneWidget);
    });

    testWidgets('an item with no title still shows something', (tester) async {
      await pump(tester, items: const [MediaSummary(id: MediaId('a'))]);

      expect(find.text('Untitled'), findsWidgets);
    });

    testWidgets('an item the server says has no poster never requests one', (
      tester,
    ) async {
      await pump(
        tester,
        items: const [MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Bare')],
      );

      expect(posterCalls(), 0);
      expect(find.text('Bare'), findsWidgets);
    });

    testWidgets('tapping a tile opens that item', (tester) async {
      final opened = <MediaSummary>[];
      await pump(
        tester,
        onOpen: opened.add,
        items: [for (var i = 0; i < 6; i++) realItems[i]],
      );

      await tester.tap(find.text('Item 3'));

      expect(opened.single.title, 'Item 3');
    });

    testWidgets('an empty category is an empty state, not a spinner', (
      tester,
    ) async {
      await pump(tester, items: const []);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Nothing in this category'), findsOneWidget);
    });

    testWidgets('a failed listing explains itself and can be retried', (
      tester,
    ) async {
      api.categoryMediaResult = CacheUnavailable(Uri.parse('http://nas/api'));

      await pump(tester);

      expect(find.text('The library is unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the app bar shows the leaf, not the full path', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryGridPage(
            api: api..categoryMediaResult = const <MediaSummary>[],
            category: const Category(
              id: CategoryId(3),
              leaf: 'Documentaries',
              name: 'Films/Documentaries',
            ),
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Documentaries'), findsOneWidget);
      expect(find.text('Films/Documentaries'), findsNothing);
    });
  });
}
