import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/category_tree_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Category _cat(
  int id, {
  int parent = 0,
  String? leaf,
  String? name,
  int media = 0,
  int files = 0,
}) => Category(
  id: CategoryId(id),
  parentId: CategoryId(parent),
  leaf: leaf ?? 'c$id',
  name: name ?? leaf ?? 'c$id',
  media: media,
  files: files,
);

void main() {
  late FakeLibraryApi api;
  final opened = <Category>[];

  setUp(() {
    api = FakeLibraryApi();
    opened.clear();
  });

  Future<void> pump(WidgetTester tester, {VoidCallback? onSignIn}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryTreePage(
          api: api,
          title: 'Attic NAS',
          onOpen: opened.add,
          onSignIn: onSignIn,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a flat list renders one row per category', (tester) async {
    api.categoriesResult = [
      _cat(1, leaf: 'Films', media: 12, files: 14),
      _cat(2, leaf: 'Shows', media: 1, files: 1),
    ];

    await pump(tester);

    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('12 · 14'), findsOneWidget);
    expect(find.text('1 · 1'), findsOneWidget);
  });

  testWidgets('a nested child is hidden until its parent is expanded', (
    tester,
  ) async {
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, parent: 1, leaf: 'Documentaries', name: 'Films/Documentaries'),
    ];

    await pump(tester);
    expect(find.text('Documentaries'), findsNothing);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();

    expect(find.text('Documentaries'), findsOneWidget);
  });

  testWidgets('a nested row shows its leaf, never its full path', (
    tester,
  ) async {
    // `name` is the full path (`Films/Documentaries`), captured against the
    // real server at M3.2. A row rendering it would print the whole path under
    // the parent it already sits beneath.
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, parent: 1, leaf: 'Documentaries', name: 'Films/Documentaries'),
    ];
    await pump(tester);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();

    expect(find.text('Films/Documentaries'), findsNothing);
  });

  testWidgets('a nested row is indented further than its parent', (
    tester,
  ) async {
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, parent: 1, leaf: 'Documentaries'),
    ];
    await pump(tester);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();

    final parent = tester.getTopLeft(find.text('Films')).dx;
    final child = tester.getTopLeft(find.text('Documentaries')).dx;

    expect(child, greaterThan(parent));
  });

  testWidgets('collapsing hides the child again', (tester) async {
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, parent: 1, leaf: 'Documentaries'),
    ];
    await pump(tester);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pump();

    expect(find.text('Documentaries'), findsNothing);
  });

  testWidgets('a category with no children has no expand affordance', (
    tester,
  ) async {
    api.categoriesResult = [_cat(1, leaf: 'Films')];

    await pump(tester);

    expect(find.byTooltip('Expand'), findsNothing);
  });

  testWidgets('tapping a row opens that category', (tester) async {
    api.categoriesResult = [_cat(1, leaf: 'Films'), _cat(2, leaf: 'Shows')];
    await pump(tester);

    await tester.tap(find.text('Shows'));

    expect(opened.single.leaf, 'Shows');
  });

  testWidgets('zero counts say nothing at all, never "0"', (tester) async {
    // library.go:73-81 returns both counts as 0 when the CACHE is unavailable,
    // exactly as it does for a genuinely empty category. "0 · 0" would state
    // as a fact something the client cannot know, so the row shows an em dash.
    api.categoriesResult = [_cat(1, leaf: 'Documentaries')];

    await pump(tester);

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0 · 0'), findsNothing);
  });

  testWidgets('a category with items but no files still reports its items', (
    tester,
  ) async {
    // BOTH counts have to be zero. `just mutants` weakened the `&&` to `||`
    // and the suite stayed green, which would have hidden every partially
    // counted category behind "no items listed".
    api.categoriesResult = [_cat(1, leaf: 'Films', media: 3)];

    await pump(tester);

    expect(find.text('3 · 0'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('a nested row is indented by exactly one step per level', (
    tester,
  ) async {
    // The arithmetic is asserted, not just the ordering: `just mutants`
    // rewrote the indent expression to `-12 + …` and to `… / 20` and no test
    // objected, because "further right than the parent" is true of both. The
    // base is everything to the left of the leaf on a root row: the design's
    // 12-point inset, the 24-point caret gutter every row carries whether or
    // not it has a caret to put in it, the 16-point folder glyph and the 8
    // points after it.
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, parent: 1, leaf: 'Documentaries'),
      _cat(3, parent: 2, leaf: 'Nature'),
    ];
    await pump(tester);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();

    final root = tester.getTopLeft(find.text('Films')).dx;
    final child = tester.getTopLeft(find.text('Documentaries')).dx;
    final grandchild = tester.getTopLeft(find.text('Nature')).dx;

    expect(root, 12 + 24 + 16 + 8);
    expect(child - root, 20);
    expect(grandchild - child, 20);
  });

  testWidgets('an empty library is an empty state, not a forever spinner', (
    tester,
  ) async {
    api.categoriesResult = <Category>[];

    await pump(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Verbatim: prose is mutable source and nothing else reads it, so `just
    // mutants` rewrote "top-level" to "top+level" and every loose assertion
    // still passed. Same class as M1's RangeError bounds.
    expect(
      find.text(
        'This server has no categories yet. Categories are the top-level '
        'folders in its media directory.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failure shows the panel, and retry re-calls exactly once', (
    tester,
  ) async {
    api.categoriesResult = CacheUnavailable(Uri.parse('http://nas/api'));
    await pump(tester);
    expect(find.text('The library is unavailable'), findsOneWidget);

    api.categoriesResult = [_cat(1, leaf: 'Films')];
    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(api.calls, ['categories', 'categories']);
    expect(find.text('Films'), findsOneWidget);
  });

  testWidgets('the load carries a cancel token, and dispose cancels it', (
    tester,
  ) async {
    api.categoriesResult = [_cat(1, leaf: 'Films')];
    await pump(tester);
    final token = api.tokens.single!;
    expect(token.isCancelled, isFalse);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(token.isCancelled, isTrue);
  });

  testWidgets('the app bar names the server', (tester) async {
    api.categoriesResult = [_cat(1, leaf: 'Films')];

    await pump(tester);

    expect(find.text('Attic NAS'), findsOneWidget);
  });

  testWidgets('the rows meet the tap-target and contrast guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    api.categoriesResult = [
      _cat(1, leaf: 'Films', media: 3, files: 3),
      _cat(2, parent: 1, leaf: 'Documentaries'),
    ];
    await pump(tester);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });

  testWidgets('typing in the filter box narrows the tree to matches', (
    tester,
  ) async {
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, leaf: 'Shows'),
    ];
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'sho');
    await tester.pumpAndSettle();

    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('Films'), findsNothing);
  });

  testWidgets('a filter that matches nothing says so', (tester) async {
    api.categoriesResult = [_cat(1, leaf: 'Films')];
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('No category matches'), findsOneWidget);
  });

  /// A filtered list is flat and nothing on it expands: every match is already
  /// showing, and a caret revealing a child the filter excluded would
  /// contradict the box above it.
  testWidgets('a filtered row has no expand caret', (tester) async {
    api.categoriesResult = [
      _cat(1, leaf: 'Films'),
      _cat(2, parent: 1, leaf: 'Docs'),
    ];
    await pump(tester);
    expect(find.byTooltip('Expand'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'film');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand'), findsNothing);
  });

  /// The button starts on the order the tree arrived in, so an untouched
  /// button changes nothing — `position` is something the server was told
  /// deliberately.
  testWidgets('the sort button cycles through its three orders', (
    tester,
  ) async {
    api.categoriesResult = [_cat(1, leaf: 'Films')];
    await pump(tester);
    expect(find.text('Folder'), findsOneWidget);

    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    expect(find.text('A–Z'), findsOneWidget);

    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();
    expect(find.text('Items'), findsOneWidget);

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();
    expect(find.text('Folder'), findsOneWidget);
  });
}
