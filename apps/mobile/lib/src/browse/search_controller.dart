import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/foundation.dart';

/// Search's state: one query, one debounce timer, one [AsyncController].
///
/// **Named `MediaSearchController` because `package:flutter/material.dart`
/// already exports a `SearchController`** — the one `SearchAnchor` drives.
/// `search_page.dart` imports both, and two `SearchController`s in scope is an
/// ambiguous-import error rather than a style question.
///
/// **The same shape as the other four screens**: the fetch, the
/// cancellation and the three renderings are `AsyncController`'s already, and
/// the only thing search adds is a `Timer`.
///
/// It imports no widget, so every case below is a plain `test()`.
class MediaSearchController extends ChangeNotifier {
  /// Searches through [api], coalescing typing over [debounce].
  ///
  /// [debounce] is injectable so tests can pass `Duration.zero` rather than
  /// waiting 300 ms per keystroke. 300 ms is the shipped value: long enough
  /// that a twelve-character word is one request rather than twelve, short
  /// enough that a person who stopped typing does not notice waiting.
  /// `docs/verification-backlog.md` row F is the device measurement that has
  /// not been made.
  MediaSearchController({
    required LibraryApi api,
    Duration debounce = const Duration(milliseconds: 300),
  }) : _api = api,
       _debounce = debounce {
    _results = AsyncController<SearchOutcome>(_fetch);
  }

  final LibraryApi _api;
  final Duration _debounce;

  late final AsyncController<SearchOutcome> _results;

  Timer? _timer;
  SearchQuery _query = const SearchQuery();

  /// What the results area should draw.
  AsyncController<SearchOutcome> get results => _results;

  /// What is currently being asked for.
  SearchQuery get query => _query;

  /// Publishes the initial state without asking the server anything.
  ///
  /// The blank query goes through [AsyncController.load] like any other, so the
  /// screen starts on "Type to search…" rather than on a spinner it can never
  /// leave — and [_fetch] short-circuits before touching [_api], so selecting
  /// the Search tab costs no request.
  Future<void> start() => _results.load();

  /// A keystroke. **Debounced**, so a word is one request.
  ///
  /// **Except a box that has just been emptied, which is immediate.** There is
  /// nothing to coalesce: [_fetch] refuses a blank query before it reaches the
  /// network, so the debounce bought no round trip and cost the user 300 ms of
  /// the *previous* query's results sitting under an empty box — while
  /// [_fetch]'s own doc claimed clearing "abandons the request it was about"
  ///. It does now, at the keystroke rather than a third of a second
  /// later.
  void setText(String text) {
    _query = _query.withText(text);
    notifyListeners();
    _timer?.cancel();
    if (_query.isBlank) {
      unawaited(_results.load());
      return;
    }
    _timer = Timer(_debounce, () => unawaited(_results.load()));
  }

  /// A scope change. **Immediate**, because picking one is deliberate rather
  /// than a byproduct of typing, and waiting 300 ms after a menu selection
  /// reads as the app having missed the tap.
  ///
  /// It cancels a pending keystroke timer first: without that, a scope picked
  /// mid-word fires this load and then the timer fires a second, identical one.
  void setField(SearchField field) {
    _query = _query.withField(field);
    notifyListeners();
    _timer?.cancel();
    unawaited(_results.load());
  }

  /// The fetch, and the one place a request is refused before it is made.
  ///
  /// **A blank or unrunnable query never reaches the network.** Both would come
  /// back `200 []` — an empty `q` short-circuits and the two numeric scopes
  /// fail closed — so the request buys nothing and costs a round
  /// trip per keystroke on the way to a query that will run.
  ///
  /// It is refused *inside the fetch* rather than by skipping the load, and the
  /// difference matters when the box is cleared mid-search:
  /// [AsyncController.load] cancels whatever is in flight, so clearing the box
  /// abandons the request it was about. Skipping the load would leave that
  /// request running and let its answer land under an empty box.
  Future<SearchOutcome> _fetch(CancelToken token) async {
    final asked = _query;
    if (asked.isBlank || !asked.isRunnable) {
      return SearchOutcome(query: asked, results: const []);
    }
    return SearchOutcome(
      query: asked,
      results: await _api.search(
        asked.wireText,
        field: asked.field,
        cancelToken: token,
      ),
    );
  }

  /// Cancels the pending keystroke **and** the request.
  ///
  /// Both halves are load-bearing and `flutter_test` gates the first for free:
  /// a test that ends with a timer still pending fails.
  @override
  void dispose() {
    _timer?.cancel();
    _results.dispose();
    super.dispose();
  }
}
