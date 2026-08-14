part of 'client.dart';

/// The four watch-state writes, in a part file.
///
/// A `part` rather than a second class, for the same reason
/// `client_playback.dart` is one: it still reaches `_uri`, `_sendJson`,
/// `_sendDelete` and `_asOurs`, so there is one URL guard and one error
/// vocabulary. The split is `file-size`'s doing — a gate warning may fall or
/// hold and never rise.
extension FileFinClientWatchState on FileFinClient {
  /// `POST /api/media/{id}/favorite` — `{"favorite": bool}`, `204`.
  ///
  /// `async` for the same reason as `categoryMedia`: a media id the server
  /// sent that cannot go in a path arrives as a failed Future rather than a
  /// synchronous throw.
  Future<void> setFavorite(
    MediaId id, {
    required bool favorite,
    CancelToken? cancelToken,
  }) async => _sendJson(
    _uri(() => urls.favorite(id), 'media id'),
    {'favorite': favorite},
    cancelToken: cancelToken,
  );

  /// `POST /api/media/{id}/rating` — **1-10 valid, 0 clears**.
  ///
  /// **The range is checked here and throws rather than sending**, because the
  /// server's own `400 rating out of range` arrives as [BadRequest], whose
  /// message says the item changed on the server — true for a progress
  /// report's `bad file index` and actively misleading here. A [RangeError]
  /// names the value and the bound instead. It is not clamped either: that
  /// would send a rating the user did not choose and report success for it.
  ///
  /// `async`, so the refusal is a failed Future like every other — but it
  /// happens **before any socket opens**, which the suite asserts by requiring
  /// the stub to have seen no request at all.
  Future<void> setRating(
    MediaId id, {
    required int rating,
    CancelToken? cancelToken,
  }) async {
    if (rating < 0 || rating > 10) {
      throw RangeError.range(rating, 0, 10, 'rating');
    }
    return _sendJson(
      _uri(() => urls.rating(id), 'media id'),
      {'rating': rating},
      cancelToken: cancelToken,
    );
  }

  /// `POST /api/media/{id}/watched` — sets or clears the flag and **keeps the
  /// resume pointer**.
  ///
  /// **This is not the same operation as [clearWatched], and collapsing the two
  /// would destroy resume positions across a whole library.** The home
  /// `continue` bucket already excludes a watched item, so
  /// `POST {"watched": false}` returns the item to *continue where you left
  /// off* while [clearWatched] drops the pointer. Observed against v0.20.3
  /// rather than merely read — `docs/field-notes.md`.
  Future<void> setWatched(
    MediaId id, {
    required bool watched,
    CancelToken? cancelToken,
  }) async => _sendJson(
    _uri(() => urls.watched(id), 'media id'),
    {'watched': watched},
    cancelToken: cancelToken,
  );

  /// `DELETE /api/media/{id}/watched` — clears the flag **and nils the
  /// pointer**.
  ///
  /// The home page's "remove from completed": a leftover pointer would bounce
  /// the item straight back into `continue`, so the pointer goes too. See
  /// [setWatched] for the measurement that separates them, and note that this
  /// is the *only* one of the four with no body — a `DELETE` carrying
  /// `{"watched": false}` would be [setWatched] wearing the wrong verb.
  Future<void> clearWatched(MediaId id, {CancelToken? cancelToken}) async =>
      _sendDelete(
        _uri(() => urls.watched(id), 'media id'),
        cancelToken: cancelToken,
      );
}
