import 'package:dpad/dpad.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four directions a remote has, and the key that means "do it".
const List<LogicalKeyboardKey> _directions = [
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowLeft,
];

/// The centre button. Android TV sends `select`; a keyboard sends `enter`, and
/// `dpad`'s default key set accepts both.
const LogicalKeyboardKey dpadSelect = LogicalKeyboardKey.select;

/// Pumps [screen] the way `FileFinApp` does on a television: dark ramp, D-pad
/// traversal wired globally, and a 1280×720 surface.
///
/// **`Dpad.wrap()` is what `app.dart` installs as `MaterialApp.builder`**, so a
/// TV test that omitted it would be exercising Flutter's default traversal
/// rather than the one that ships — and directional movement is the entire
/// subject of these suites.
Future<void> pumpTv(
  WidgetTester tester,
  Widget screen, {
  Size surface = const Size(1280, 720),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: fileFinTheme(FileFinPalette.dark),
      builder: Dpad.wrap(),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

/// What the focused control is, named the way a person would name it.
///
/// A label rather than a `FocusNode`, because a node is an identity a test
/// cannot assert anything readable about. The first `Text` under the focused
/// subtree is the control's own words; failing that its `Tooltip`, then its
/// `Icon`. A focusable with none of the three is reported as `?`, which is
/// itself a finding — a remote user has nothing to go on either.
String focusedLabel(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return '<none>';
  final scope = find.byWidget(context.widget);
  for (final text in tester.widgetList<Text>(
    find.descendant(of: scope, matching: find.byType(Text)),
  )) {
    if (text.data != null && text.data!.isNotEmpty) return text.data!;
  }
  for (final tip in tester.widgetList<Tooltip>(
    find.descendant(of: scope, matching: find.byType(Tooltip)),
  )) {
    if (tip.message != null && tip.message!.isNotEmpty) return tip.message!;
  }
  for (final icon in tester.widgetList<Icon>(
    find.descendant(of: scope, matching: find.byType(Icon)),
  )) {
    if (icon.semanticLabel != null) return icon.semanticLabel!;
    if (icon.icon != null) return 'icon:${icon.icon!.codePoint}';
  }
  return '?';
}

/// Every control the D-pad can actually get to, as a breadth-first search of
/// the directional focus graph.
///
/// **A walk, not an inventory of `Focus` widgets, and the difference is the
/// whole point.** A control can be perfectly focusable and still be
/// unreachable — nothing above it in the traversal order points at it, or a
/// `FocusScope` swallows the direction that would leave it. Only pressing the
/// keys proves a person with a remote can arrive. It found both: the rail
/// trapped focus inside a scope, and the shell's panes could not be re-entered.
///
/// **It returns to each node before trying the next direction from it**, and
/// two simpler versions failed for want of that. Cycling the four directions
/// one press at a time walks a three-item column as Home → Library → Home →
/// Library for ever, because `up` undoes every `down`. Running each direction
/// to exhaustion instead escapes the column but then presses `up` from
/// wherever it landed, which on a rail-plus-content layout means never going
/// back for the rail's top half. Both reported live controls as unreachable,
/// which is the one result a reachability check must never invent.
///
/// Re-focusing a node directly is not cheating: what is being proved is that
/// every control is one key press from another reachable control, which is
/// exactly reachability in the graph the remote actually walks.
Future<Set<String>> dpadReachable(WidgetTester tester) async {
  final start = FocusManager.instance.primaryFocus;
  if (start == null) return {};
  final seen = <String, FocusNode>{focusedLabel(tester): start};
  final queue = <FocusNode>[start];
  while (queue.isNotEmpty) {
    final from = queue.removeAt(0);
    for (final direction in _directions) {
      from.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(direction);
      await tester.pumpAndSettle();
      final landed = FocusManager.instance.primaryFocus;
      final label = focusedLabel(tester);
      if (landed != null && label != '<none>' && !seen.containsKey(label)) {
        seen[label] = landed;
        queue.add(landed);
      }
    }
  }
  return seen.keys.toSet();
}

/// Moves focus until [label] holds it, then presses the centre button.
///
/// Fails with the labels it *did* reach rather than with a bare timeout: on a
/// television "the button does nothing" and "the button cannot be focused"
/// look identical from the sofa, and the reachable set is what tells them
/// apart.
Future<void> dpadActivate(WidgetTester tester, String label) async {
  await dpadFocus(tester, label);
  await tester.sendKeyEvent(dpadSelect);
  await tester.pumpAndSettle();
}

/// Leaves focus on [label], having got there with arrow keys.
///
/// The same search as [dpadReachable], stopping at the target — so the control
/// is left focused by a key press rather than by a direct request.
Future<void> dpadFocus(WidgetTester tester, String label) async {
  if (focusedLabel(tester) == label) return;
  final start = FocusManager.instance.primaryFocus;
  if (start != null) {
    final seen = <String, FocusNode>{focusedLabel(tester): start};
    final queue = <FocusNode>[start];
    while (queue.isNotEmpty) {
      final from = queue.removeAt(0);
      for (final direction in _directions) {
        from.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(direction);
        await tester.pumpAndSettle();
        final landed = FocusManager.instance.primaryFocus;
        final here = focusedLabel(tester);
        if (here == label) return;
        if (landed != null && here != '<none>' && !seen.containsKey(here)) {
          seen[here] = landed;
          queue.add(landed);
        }
      }
    }
    fail(
      'D-pad never reached "$label". It reached: ${seen.keys.toList()..sort()}',
    );
  }
  fail('Nothing had focus, so "$label" could not be looked for.');
}
