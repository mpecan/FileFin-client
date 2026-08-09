part of 'client.dart';

/// F10's four writes, in a part file.
///
/// A `part` rather than a second class, for the same reason
/// `client_playback.dart` is one: it still reaches `_uri`, `_sendJson`,
/// `_sendDelete` and `_asOurs`, so there is one URL guard and one error
/// vocabulary. The split is `file-size`'s doing — a gate warning may fall or
/// hold and never rise.
extension FileFinClientWatchState on FileFinClient {
  /// `POST /api/media/{id}/favorite` — `{"favorite": bool}`, `204`
  /// (`media.go:394`).
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

  /// `POST /api/media/{id}/rating` — **1-10 valid, 0 clears** (`media.go:417`).
  ///
  /// **The range is checked here, and it throws rather than sending.** The
  /// server answers anything outside `0..10` with `400 rating out of range`
  /// (`media.go:425`, measured at M6.0/E-6 at −1, 0, 10, 11, 99 and
  /// `-2147483648`), and a `400` arrives in this package as [BadRequest],
  /// whose message says the item changed on the server. That sentence is true
  /// for the `bad file index` a progress report can get and actively
  /// misleading here: nothing changed, the caller asked for a rating that
  /// cannot exist. A [RangeError] names the value and the bound instead.
  ///
  /// It is not clamped, either. Clamping would send a rating the user did not
  /// choose and report success for it.
  ///
  /// `async`, so the refusal is a failed Future like every other refusal on
  /// this client — but it happens **before any socket opens**, which is what
  /// `client_watch_state_test.dart` asserts by requiring the stub to have seen
  /// no request at all.
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
  /// resume pointer** (`media.go:463-483`).
  ///
  /// **This is not the same operation as [clearWatched], and collapsing the
  /// two would destroy resume positions across a whole library.** Upstream's
  /// own comment says why (`media.go:458-462`): the home `continue` bucket
  /// already excludes a watched item, so `POST {"watched": false}` returns the
  /// item to *continue where you left off*.
  ///
  /// **Observed against v0.20.3, not merely read** (M6.0/E-5 — the first time
  /// anything in this repository exercised the distinction). On a two-file show
  /// with the pointer at file 0, 45 seconds in: `POST {"watched": true}` put it
  /// in `completed` with the pointer untouched; `POST {"watched": false}` put
  /// it back in `continue` **still at 45 seconds**, in `meta.json` as well as
  /// in the detail payload. Then [clearWatched] left it in no home row at all
  /// with the pointer gone.
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
  /// pointer** (`media.go:485-499`).
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
