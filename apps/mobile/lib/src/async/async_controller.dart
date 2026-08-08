import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/async/ui_state.dart';
import 'package:flutter/foundation.dart';

/// One screen, one asynchronous fetch, one cancel token.
///
/// **A hand-written `ChangeNotifier` rather than a state-management package,
/// and the decision is recorded in `docs/architecture.md` as D-Q1.** M3's real
/// screens are three, each is exactly this shape, and `ChangeNotifier` /
/// `ListenableBuilder` ship with the framework. A framework would bring surface
/// this app never constructs — which §1 and §5 both object to — and, less
/// obviously, would *shrink* what the mutation gate reaches: framework-internal
/// branching is not in our diff, so no mutant is ever generated for it, while
/// the branching below produces mutants that our tests have to kill.
///
/// It imports no widget on purpose. The whole class is testable with plain
/// `test()`, no binding and no pumping.
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
  /// the newer answer with stale data and nothing on screen would say so. The
  /// generation check after the await covers the remaining window — a request
  /// already past the point of cancellation still must not win.
  ///
  /// **A `RequestCancelled` is dropped, not reported**, and that is the entire
  /// reason `filefin_api` gives cancellation its own variant: it means the user
  /// navigated away or a newer load superseded this one, and rendering
  /// "something went wrong" for it would put an error panel on screen every
  /// time someone scrolled.
  ///
  /// What is left on screen in that case is the `UiLoading` published below,
  /// **not** whatever was there before — this method publishes before it
  /// awaits, so the previous data is already gone. Said explicitly because an
  /// earlier draft claimed the opposite and a test caught it. The two cases
  /// that actually reach that arm are a dispose (nothing is on screen) and a
  /// supersede (the newer load publishes its own state).
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
