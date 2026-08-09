import 'package:filefin_core/filefin_core.dart';
import 'package:meta/meta.dart';

/// What the search screen is asking for right now: the text and the scope.
///
/// One value rather than two fields on the controller, because the pair is what
/// a request is made of and splitting it is how a screen ends up sending last
/// keystroke with this scope.
///
/// **No `==`, no `hashCode`, no `toString`, and their absence is §1 rather than
/// an oversight.** Nothing compares two queries or puts one in a set: the
/// controller replaces the whole value on every change and `SearchOutcome`
/// carries it along for display. The first draft had all three, and
/// `just mutants` said so plainly — swapping `Object.hash`'s two arguments
/// survived the entire suite, because a hash consistent with an equality
/// nobody calls cannot be told from any other. Deleting the members was the
/// answer; asserting a particular `Object.hash` output would have pinned an
/// implementation detail of the SDK to make a gate go quiet.
@immutable
class SearchQuery {
  /// A query over [field] for [text]. The default is an empty search of
  /// everything, which is what a freshly opened screen holds.
  const SearchQuery({this.text = '', this.field = SearchField.all});

  /// Exactly what is in the box, untrimmed.
  final String text;

  /// Which `?field=` the server is told.
  final SearchField field;

  /// What actually goes on the wire.
  ///
  /// Trimmed, because the two numeric scopes `TrimSpace` before parsing
  /// (`db/search.go:36,43`) while the nine text scopes do **not** — `likePattern`
  /// only lowercases — so `" ada "` unqueried would search titles for a string
  /// with spaces in it and find nothing, on a query the user would swear they
  /// typed correctly.
  String get wireText => text.trim();

  /// Nothing has been typed. The server short-circuits an empty `q` to
  /// `200 []` (`db/search.go:17-19`), so this client does not ask at all.
  bool get isBlank => wireText.isEmpty;

  /// Whether the server will actually **run** this query, as opposed to
  /// answering `200 []` because it could not read the input (M6.0/E-4).
  bool get isRunnable => searchIsRunnable(text, field: field);

  /// The same query with different text.
  SearchQuery withText(String text) => SearchQuery(text: text, field: field);

  /// The same text in a different scope.
  SearchQuery withField(SearchField field) =>
      SearchQuery(text: text, field: field);
}

/// One completed search, **carrying the query it answers**.
///
/// The query travels with the results rather than being read off the
/// controller when the caption is drawn, and that is the whole reason this
/// type exists: the box can change between a request going out and its answer
/// coming back, and a screen that captioned "No matches for X" with whatever is
/// in the box now would name a query nobody ran.
@immutable
class SearchOutcome {
  /// [results] is what the server returned for [query].
  const SearchOutcome({required this.query, required this.results});

  /// The query these results answer.
  final SearchQuery query;

  /// What the server sent, in its own order.
  final List<MediaSummary> results;
}
