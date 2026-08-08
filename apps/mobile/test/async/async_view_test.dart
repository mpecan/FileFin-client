import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Uri.parse('https://nas.local/api/categories');

  Widget host(AsyncController<String> controller, {VoidCallback? onSignIn}) =>
      MaterialApp(
        home: Scaffold(
          body: AsyncView<String>(
            controller: controller,
            onSignIn: onSignIn,
            builder: (_, value) => Text(value),
          ),
        ),
      );

  testWidgets('a controller that has not loaded shows a spinner', (
    tester,
  ) async {
    final controller = AsyncController<String>(
      (_) => Completer<String>().future,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('data reaches the builder, and the spinner goes', (tester) async {
    final controller = AsyncController<String>((_) async => 'Films');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await controller.load();
    await tester.pump();

    expect(find.text('Films'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failure shows the panel with the described words', (
    tester,
  ) async {
    final controller = AsyncController<String>(
      (_) async => throw CacheUnavailable(url),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await controller.load();
    await tester.pump();

    expect(find.text('The library is unavailable'), findsOneWidget);
    expect(find.textContaining('possibly'), findsOneWidget);
  });

  testWidgets('retry calls load exactly once per press', (tester) async {
    // Once, not twice: a retry that fires two requests doubles the load on a
    // server that has just told us it is struggling, and the second answer
    // silently overwrites the first.
    var calls = 0;
    final controller = AsyncController<String>((_) async {
      calls += 1;
      throw CacheUnavailable(url);
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await controller.load();
    await tester.pump();

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(calls, 2, reason: 'the first load plus exactly one retry');
  });

  testWidgets('a non-retryable failure offers no retry', (tester) async {
    // `NotFound` will answer the same way forever. A button that cannot work
    // is worse than no button: it says the app expects it to.
    final controller = AsyncController<String>(
      (_) async => throw NotFound(url),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await controller.load();
    await tester.pump();

    expect(find.text('Try again'), findsNothing);
    expect(find.text('Not on the server any more'), findsOneWidget);
  });

  testWidgets('SessionExpired offers sign-in and NOT retry', (tester) async {
    // F3 has already re-authenticated and retried once by the time this
    // exists, so a retry button would repeat exactly what did not work.
    var signIns = 0;
    final controller = AsyncController<String>(
      (_) async => throw SessionExpired(url),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, onSignIn: () => signIns += 1));
    await controller.load();
    await tester.pump();

    expect(find.text('Try again'), findsNothing);
    await tester.tap(find.text('Sign in'));

    expect(signIns, 1);
  });

  testWidgets('with no sign-in route wired, the panel still explains itself', (
    tester,
  ) async {
    // A screen that has nowhere to send the user must still say what happened
    // rather than rendering a button that does nothing.
    final controller = AsyncController<String>(
      (_) async => throw SessionExpired(url),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await controller.load();
    await tester.pump();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Please sign in again'), findsOneWidget);
  });

  testWidgets('the view repaints when the controller changes underneath it', (
    tester,
  ) async {
    // `ListenableBuilder` rather than a StatefulWidget calling setState: the
    // subscription is what makes this a view of the controller rather than a
    // snapshot of it, and a missing one shows a spinner forever.
    var call = 0;
    final controller = AsyncController<String>((_) async {
      call += 1;
      return 'load $call';
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    await controller.load();
    await tester.pump();
    expect(find.text('load 1'), findsOneWidget);

    await controller.load();
    await tester.pump();

    expect(find.text('load 2'), findsOneWidget);
  });

  testWidgets('the error panel meets the tap-target guideline', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = AsyncController<String>(
      (_) async => throw CacheUnavailable(url),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await controller.load();
    await tester.pump();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });
}
