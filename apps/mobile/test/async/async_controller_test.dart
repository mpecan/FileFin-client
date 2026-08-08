import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plain `test()`, no `testWidgets` — the controller holds a port and a cancel
/// token and imports no widget, so it is a plain object under test. Nothing
/// here pumps a frame or needs a binding, which is the point of the boundary.
void main() {
  final url = Uri.parse('https://example.invalid/api/categories');

  test('a fresh controller is loading, before anything is asked for', () {
    final controller = AsyncController<int>((_) async => 1);
    addTearDown(controller.dispose);

    expect(controller.state, isA<UiLoading<int>>());
  });

  test('a successful load ends in UiData and notifies', () async {
    var notifications = 0;
    final controller = AsyncController<int>((_) async => 7)
      ..addListener(() => notifications += 1);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state, isA<UiData<int>>());
    expect((controller.state as UiData<int>).value, 7);
    expect(notifications, greaterThanOrEqualTo(1));
  });

  test('a failure ends in UiFailure carrying the exception itself', () async {
    final controller = AsyncController<int>(
      (_) async => throw NotFound(url),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state, isA<UiFailure<int>>());
    expect((controller.state as UiFailure<int>).error, isA<NotFound>());
  });

  test('load() passes a live token, and cancels the previous one', () async {
    final tokens = <CancelToken>[];
    final gate = Completer<int>();
    final controller = AsyncController<int>((token) {
      tokens.add(token);
      return tokens.length == 1 ? gate.future : Future.value(2);
    });
    addTearDown(controller.dispose);

    unawaited(controller.load());
    await controller.load();

    expect(tokens, hasLength(2));
    expect(tokens.first.isCancelled, isTrue, reason: 'the superseded load');
    expect(tokens.last.isCancelled, isFalse);
    gate.complete(1);
  });

  test('a superseded load does not overwrite the newer result', () async {
    // The reason `load()` cancels rather than merely ignoring: two in-flight
    // requests can finish in either order, and the older one finishing last
    // would show stale data with no way to tell.
    final gate = Completer<int>();
    var call = 0;
    final controller = AsyncController<int>((_) {
      call += 1;
      return call == 1 ? gate.future : Future.value(2);
    });
    addTearDown(controller.dispose);

    unawaited(controller.load());
    await controller.load();
    gate.complete(1);
    await Future<void>.delayed(Duration.zero);

    expect((controller.state as UiData<int>).value, 2);
  });

  test('RequestCancelled is dropped: it is not a failure', () async {
    // The variant exists precisely so a UI can tell "the user navigated away"
    // from "something broke" (filefin_api's errors.dart says so). Showing an
    // error panel for it would put "something went wrong" on screen every time
    // someone scrolled.
    final controller = AsyncController<int>(
      (_) async => throw RequestCancelled(url),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state, isA<UiLoading<int>>());
  });

  test('a cancelled reload shows the spinner, never an error panel', () async {
    // What cancellation does NOT do is the assertion. `load()` publishes
    // UiLoading before it awaits, so a cancelled reload leaves the spinner up
    // rather than restoring the previous data — this test says so out loud
    // because the first version of the doc comment claimed otherwise and this
    // is what caught it. The property that matters is that the user is never
    // told something broke because they navigated away.
    var call = 0;
    final controller = AsyncController<int>((_) async {
      call += 1;
      if (call == 1) return 5;
      throw RequestCancelled(url);
    });
    addTearDown(controller.dispose);

    await controller.load();
    await controller.load();

    expect(controller.state, isA<UiLoading<int>>());
    expect(controller.state, isNot(isA<UiFailure<int>>()));
  });

  test('dispose cancels the in-flight token (NF5)', () async {
    late CancelToken captured;
    final gate = Completer<int>();
    final controller = AsyncController<int>((token) {
      captured = token;
      return gate.future;
    });

    unawaited(controller.load());
    controller.dispose();

    expect(captured.isCancelled, isTrue);
    gate.complete(1);
  });

  test('a load that lands after dispose notifies nobody', () async {
    // ChangeNotifier asserts on notifyListeners() after dispose, so this is
    // not a nicety: without the guard, a screen closed while a request was in
    // flight throws in debug and the crash names the notifier, not the screen.
    var notifications = 0;
    final gate = Completer<int>();
    final controller = AsyncController<int>((_) => gate.future)
      ..addListener(() => notifications += 1);

    final pending = controller.load();
    controller.dispose();
    gate.complete(1);
    await pending;

    expect(notifications, 1, reason: 'only the UiLoading before dispose');
  });

  test('a failure that lands after dispose notifies nobody either', () async {
    var notifications = 0;
    final gate = Completer<int>();
    final controller = AsyncController<int>((_) => gate.future)
      ..addListener(() => notifications += 1);

    final pending = controller.load();
    controller.dispose();
    gate.completeError(NotFound(url));
    await pending;

    expect(notifications, 1);
  });

  test('retrying after a failure goes back through loading', () async {
    final seen = <UiState<int>>[];
    var call = 0;
    late final AsyncController<int> controller;
    controller = AsyncController<int>((_) async {
      call += 1;
      if (call == 1) throw NotFound(url);
      return 3;
    })..addListener(() => seen.add(controller.state));
    addTearDown(controller.dispose);

    await controller.load();
    await controller.load();

    expect(seen.map((s) => s.runtimeType), [
      UiLoading<int>,
      UiFailure<int>,
      UiLoading<int>,
      UiData<int>,
    ]);
  });
}
