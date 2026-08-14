import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/async/ui_state.dart';
import 'package:flutter/foundation.dart';

/// One screen, one asynchronous fetch, one cancel token.
///
/// **A hand-written `ChangeNotifier` rather than a state-management package**
/// — D9, with the retirement condition in `docs/architecture.md`.
///
/// It imports no widget on purpose, so the whole class is testable with plain
/// `test()`: no binding, no pumping.
class AsyncController<T> extends ChangeNotifier {
  /// Fetches through [_fetch], handing it a token it must pass to the port.
  AsyncController(this._fetch);

  final Future<T> Function(CancelToken) _fetch;

  UiState<T> _state = UiLoading<T>();

  CancelToken? _token;

  bool _disposed = false;

  /// What the view should draw right now.
  UiState<T> get state => _state;

  /// Cancels anything in flight, then fetches again.
  ///
  /// **Cancelling rather than ignoring is the point.** Two in-flight requests
  /// can finish in either order, so an older one landing last would overwrite
  /// the newer answer with stale data and say nothing. The generation check
  /// after the await covers the remaining window.
  ///
  /// **A `RequestCancelled` is dropped, not reported** — that is the whole
  /// reason cancellation has its own variant. Rendering "something went wrong"
  /// for it would put an error panel on screen every time someone scrolled.
  /// What is left showing is the `UiLoading` published below, **not** what was
  /// there before: this publishes before it awaits.
  Future<void> load() async {
    _token?.cancel();
    final token = CancelToken();
    _token = token;
    _publish(UiLoading<T>());
    try {
      final value = await _fetch(token);
      if (!identical(_token, token)) return;
      _publish(UiData<T>(value));
    } on RequestCancelled {
      // Deliberately empty; the doc comment above says why.
    } on FileFinApiException catch (error) {
      if (!identical(_token, token)) return;
      _publish(UiFailure<T>(error));
    }
  }

  /// Publishes [value] as the current data, with no fetch.
  ///
  /// **F9's "without a full refetch" needs exactly this and nothing more.** The
  /// player hands its screen a state folded through the server's own engine,
  /// and re-reading the detail to display it would be the round trip F9 says
  /// not to make. It does not touch [_token]: the only caller runs from a
  /// completed route, long after `initState`'s load has published, so there is
  /// no in-flight request for a later publish to lose a race with — and a
  /// cancel here would be a branch no test could reach.
  void replace(T value) => _publish(UiData<T>(value));

  /// Cancels in flight work and refuses to notify afterwards (NF5).
  ///
  /// `ChangeNotifier` asserts on `notifyListeners()` after disposal, so without
  /// the flag a screen closed mid-request throws in debug — and the crash names
  /// the notifier rather than the screen that closed.
  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }

  void _publish(UiState<T> next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }
}
