/// The `field` selector of `GET /api/search` — `searchWhere`,
/// `db/search.go:34-86`.
///
/// This vocabulary is **wider than SPEC.md §3.2 lists**; the full table is in
/// `docs/server-api.md`.
///
/// It is an enum rather than a `String` because an unrecognised `field`
/// **silently degrades to `all`** upstream rather than erroring, so a typo
/// produces plausible results that are quietly wrong — the worst failure a
/// search box can have.
enum SearchField {
  /// Title, description, plot, language, country, director, writer, plus the
  /// actor/genre/tag facets. Also what any unrecognised value falls back to.
  all,

  /// Exact `year =`. A non-numeric `q` yields no rows rather than an error.
  year,

  /// `year BETWEEN d AND d+9`, `d` floored to the decade (`db/search.go:47`).
  /// `q` may carry a trailing `s`, so `1990s` works.
  decade,

  /// `title LIKE`.
  title,

  /// `description LIKE`.
  description,

  /// The `actor` facet. Note the wire word is `cast`, not `actor`.
  cast,

  /// The `genre` facet.
  genre,

  /// The `tag` facet.
  tag,

  /// `language LIKE`.
  language,

  /// `director LIKE`.
  director,

  /// `writer LIKE`.
  writer;

  /// The exact token the server expects in `?field=`.
  String get wire => name;
}

/// The grammar `strconv.Atoi` accepts: an optional sign and at least one ASCII
/// digit, and nothing else at all.
final RegExp _atoiGrammar = RegExp(r'^[+-]?[0-9]+$');

/// [value] as Go's `strconv.Atoi` would read it, or null where it would error.
///
/// Two steps rather than one, because `int.tryParse` alone is wider than
/// `Atoi`: the grammar refuses what `Atoi` refuses, and the parse then applies
/// the 64-bit range check both share.
int? _atoi(String value) =>
    _atoiGrammar.hasMatch(value) ? int.tryParse(value) : null;

/// [query] as the `decade` scope reads it —
/// `TrimSuffix(ToLower(TrimSpace(q)), "s")` (`db/search.go:43`).
///
/// **One `s`, not every trailing `s`.** `TrimSuffix` removes a single
/// occurrence, so `1990s` is a decade and `1990ss` is not — measured live at
/// M6.0/E-4, where `q=2020ss&field=decade` returned no rows while
/// `q=2020s` returned one.
String _withoutDecadeSuffix(String query) {
  final lower = query.toLowerCase();
  return lower.endsWith('s') ? lower.substring(0, lower.length - 1) : lower;
}

/// Whether the server will actually **run** a search for [query] in [field], as
/// opposed to answering `200 []` because it could not read the input.
///
/// Three ways a search returns nothing and only one is "nothing matched": an
/// empty `q` short-circuits (`db/search.go:17-19`), and the two numeric scopes
/// fail closed. On screen all three look like an empty library, so the client
/// has to know the difference in order to say it. It mirrors `strconv.Atoi`'s
/// grammar rather than `int.tryParse`, which differs on exactly one input
/// class (`docs/field-notes.md`).
///
/// The switch has no default arm, so a twelfth [SearchField] cannot be added
/// without deciding whether it is numeric.
bool searchIsRunnable(String query, {required SearchField field}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return false;
  return switch (field) {
    SearchField.year => _atoi(trimmed) != null,
    SearchField.decade => _atoi(_withoutDecadeSuffix(trimmed)) != null,
    SearchField.all ||
    SearchField.title ||
    SearchField.description ||
    SearchField.cast ||
    SearchField.genre ||
    SearchField.tag ||
    SearchField.language ||
    SearchField.director ||
    SearchField.writer => true,
  };
}
