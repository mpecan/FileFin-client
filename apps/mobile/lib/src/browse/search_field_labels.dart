import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:meta/meta.dart';

/// The words the search screen puts on screen for one [SearchField].
///
/// **Every switch here is exhaustive with no default arm, and that is the
/// point of the file.** `db/search.go:70` degrades an unrecognised `field` to
/// `all` rather than erroring, so a scope the client can send but cannot
/// describe produces plausible results under the wrong label — the worst
/// failure a search box has. With no `_ =>` arm, a twelfth `SearchField` stops
/// compilation here instead.

/// The scope's name in the picker.
String searchFieldLabel(SearchField field) => switch (field) {
  SearchField.all => 'Everything',
  SearchField.title => 'Title',
  SearchField.description => 'Description',
  // The wire word is `cast`; the label is what a person calls it.
  SearchField.cast => 'Cast',
  SearchField.genre => 'Genre',
  SearchField.tag => 'Tag',
  SearchField.language => 'Language',
  SearchField.director => 'Director',
  SearchField.writer => 'Writer',
  SearchField.year => 'Year',
  SearchField.decade => 'Decade',
};

/// The scope as a plural noun, for use inside a sentence.
///
/// Separate from [searchFieldLabel] because "No matches for *ada* in Cast"
/// reads as a proper noun and "…in cast" reads as English, and a single string
/// cannot be both a menu entry and a fragment.
/// Public only so a test can reach it; nothing outside this library calls
/// it (§5, `public_member_no_consumer`).
@visibleForTesting
String searchFieldNoun(SearchField field) => switch (field) {
  SearchField.all => 'anything',
  SearchField.title => 'titles',
  SearchField.description => 'descriptions',
  SearchField.cast => 'the cast',
  SearchField.genre => 'genres',
  SearchField.tag => 'tags',
  SearchField.language => 'languages',
  SearchField.director => 'directors',
  SearchField.writer => 'writers',
  SearchField.year => 'years',
  SearchField.decade => 'decades',
};

/// What the two numeric scopes parse `q` as, or null for the nine text scopes.
///
/// `year` runs `strconv.Atoi(TrimSpace(q))` and `decade` runs it after
/// stripping one trailing `s`; either failing returns **no rows and no error**
/// (`db/search.go:36-48`). The nine text scopes run any non-empty `q`, so they
/// have no unit to fail to parse.
/// Public only so a test can reach it; nothing outside this library calls
/// it (§5, `public_member_no_consumer`).
@visibleForTesting
String? searchFieldNumericUnit(SearchField field) => switch (field) {
  SearchField.year => 'year',
  SearchField.decade => 'decade',
  SearchField.all ||
  SearchField.title ||
  SearchField.description ||
  SearchField.cast ||
  SearchField.genre ||
  SearchField.tag ||
  SearchField.language ||
  SearchField.director ||
  SearchField.writer => null,
};

/// What the screen says when there are no results to draw, or null when there
/// are.
///
/// **Three ways a search shows nothing and only one of them is "nothing
/// matched".** They are indistinguishable on the wire — all three are a `200`
/// with an empty array, or no request at all — so if the client does not tell
/// them apart nobody can. A user who typed `nineteen` into the Year scope gets
/// told why, instead of concluding their library is empty.
String? searchNotice(SearchOutcome outcome) {
  final query = outcome.query;
  if (query.isBlank) {
    return 'Type to search ${searchFieldNoun(query.field)}.';
  }
  final unit = searchFieldNumericUnit(query.field);
  if (unit != null && !query.isRunnable) {
    return '“${query.wireText}” is not a $unit, so nothing was searched for. '
        'A $unit is a whole number.';
  }
  if (outcome.results.isEmpty) {
    return 'No matches for “${query.wireText}” in '
        '${searchFieldNoun(query.field)}.';
  }
  return null;
}
