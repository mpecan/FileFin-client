part of 'client.dart';

/// The read-only library routes, in a part file.
///
/// A `part` rather than a second class, exactly as `client_playback.dart` is
/// one: everything here reaches `_send`, `_uri`, `_one`, `_many` and
/// `_asOurs`, so there is one URL guard and one error vocabulary for the whole
/// client. The split is `file-size`'s doing — `client.dart` was at 363 lines
/// and M6 adds six routes to it, and a gate warning may fall or hold and never
/// rise.
///
/// "Read-only" is C4's word: none of these mutates anything on the server. The
/// writes are `client_watch_state.dart` and `postProgress`.
extension FileFinClientBrowse on FileFinClient {
  /// `GET /api/categories` — the flat list; the tree is assembled client-side.
  Future<List<Category>> categories({CancelToken? cancelToken}) => _send(
    urls.categories,
    (r, url) => FileFinClient._many(r, url, Category.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/category/{id}/media` — direct children, not the subtree.
  ///
  /// `async` rather than a plain arrow so that a rejected identifier arrives
  /// as a **failed Future** and not as a synchronous throw. `_uri` runs before
  /// the first await, and a caller awaiting this method should never have to
  /// wrap the call site in a try as well.
  Future<List<MediaSummary>> categoryMedia(
    CategoryId id, {
    CancelToken? cancelToken,
  }) async => _send(
    _uri(() => urls.categoryMedia(id), 'category id'),
    (r, url) => FileFinClient._many(r, url, MediaSummary.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/media/{id}` — the full detail payload.
  ///
  /// `async` for the same reason as [categoryMedia].
  Future<MediaDetail> mediaDetail(
    MediaId id, {
    CancelToken? cancelToken,
  }) async => _send(
    _uri(() => urls.mediaDetail(id), 'media id'),
    (r, url) => FileFinClient._one(r, url, MediaDetail.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/media/{id}/poster` — image bytes, or **null when there is no
  /// poster**.
  ///
  /// **`null` is a 404 and a 404 is normal here.** `docs/server-api.md` records
  /// it: an un-enriched library has no artwork, and the server answers that
  /// with a 404 rather than an empty body. Surfacing it as an error would put a
  /// failure in front of every tile of a freshly imported library. Every OTHER
  /// failure stays in the sealed hierarchy — a 503 is still `CacheUnavailable`,
  /// so "the server is rebuilding" never reads as "you have no artwork".
  ///
  /// [size] is a hint and not a contract (`media.go:351`): the server serves
  /// the pre-built variant **if it exists** and silently falls back otherwise,
  /// so the returned image may be any dimensions. It is only put on the wire
  /// when asked for, because an absent value and an unrecognised one behave
  /// identically and sending one always would make every request look like a
  /// request for a variant.
  ///
  /// `async` for the same reason as [categoryMedia]: a rejected identifier
  /// arrives as a failed Future. A grid building 5000 tiles must not have to
  /// wrap the call in a `try` as well as an `await`.
  Future<Uint8List?> posterBytes(
    MediaId id, {
    PosterSize? size,
    CancelToken? cancelToken,
  }) async {
    final url = _uri(() => urls.poster(id, size: size), 'media id');
    try {
      final response = await _dio.getUri<List<int>>(
        url,
        cancelToken: cancelToken,
        // NOT `_send`. That path decodes JSON, and a poster is bytes; running
        // an image through `jsonDecode` would report a broken server for a
        // working one. `ResponseType.bytes` also stops dio deciding for itself
        // what to do with the body based on the content type.
        options: Options(responseType: ResponseType.bytes),
      );
      FileFinClient._refuseHtml(response.headers, url);
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final mapped = _asOurs(e, url);
      if (mapped is NotFound) return null;
      throw mapped;
    }
  }

  /// `GET /api/home` — continue / favourites / completed in one call.
  ///
  /// **Served from the `user_state` mirror, not from `meta.json`**
  /// (`media.go:227` -> `db.HomeBuckets`), and the mirror upsert on every write
  /// is best-effort (`media.go:166-181`). So a `204` from a watch-state write
  /// does not prove what this will answer, and M6.0/E-2 measured a copy where
  /// the two disagreed in both directions. A caller that wants the rows right
  /// after a write has to re-read them; it cannot predict them.
  Future<HomeRows> home({CancelToken? cancelToken}) => _send(
    urls.home,
    (r, url) => FileFinClient._one(r, url, HomeRows.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/search?q=&field=` — `MediaSummary[]`, year then title.
  ///
  /// Both parameters always go on the wire. An empty `q` answers `[]` rather
  /// than the whole library and an unrecognised `field` degrades silently to
  /// `all` (`db/search.go:17-19`, `:74`), so nothing here second-guesses the
  /// caller: `searchIsRunnable` in `filefin_core` is what decides whether a
  /// request is worth making, and this method sends what it is given.
  Future<List<MediaSummary>> search(
    String query, {
    SearchField field = SearchField.all,
    CancelToken? cancelToken,
  }) => _send(
    urls.search(query, field: field),
    (r, url) => FileFinClient._many(r, url, MediaSummary.fromJson),
    cancelToken: cancelToken,
  );
}
