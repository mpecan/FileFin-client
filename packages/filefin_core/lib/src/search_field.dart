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
