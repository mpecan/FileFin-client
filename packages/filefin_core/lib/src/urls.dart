import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/search_field.dart';
import 'package:meta/meta.dart';

/// Every path this client will ever request, written out in full, in one class.
///
/// Every interpolated value goes through [_seg]. A path template is a string,
/// so a parameter containing `/` would otherwise merge into the template and be
/// split back out as two segments — the request would address a different route
/// and the failure would arrive as a 404 from somewhere else. `MediaId` comes
/// straight off the wire and defaults to `MediaId('')` (§8), so that is not a
/// hypothetical.
///
/// One class and one full literal per route is a structural decision, not a
/// stylistic one. `undocumented_endpoint` (`tool/check-constitution.sh`, §8)
/// greps string literals containing `/api/` and checks each against
/// `docs/server-api.md`; it cannot reconstruct a path assembled from pieces. So
/// `'$_media/hls/index.m3u8'` would be invisible to the gate — correct today,
/// and unchecked forever after. The repetition below is what keeps every route
/// answerable to the document that cites its upstream line.
abstract final class ApiPaths {
  /// Percent-encodes one interpolated path parameter, and rejects the three
  /// values that no encoding can make safe.
  ///
  /// [FileFinUrls._resolve] decodes each segment again before handing it to
  /// `Uri`, which re-encodes it — so the round trip is lossless and `Uri`
  /// remains the only thing that decides the final escaping. That works for
  /// every character; it does not work for `''`, `'.'` and `'..'`, which are
  /// not characters but *whole segments* `Uri` deletes.
  ///
  /// `Uri.encodeComponent` leaves `.` alone (RFC-unreserved), and Dart's `Uri`
  /// removes dot segments unconditionally — including from their escaped form,
  /// so writing `%2E%2E` does not help either — `Uri.parse('https://h/a/b/'
  /// '%2E%2E/x').path` is `/a/x`, and `urls_test.dart` pins that with the real
  /// route rather than this stand-in, which is spelled with `a/b` only so the
  /// §8 `undocumented_endpoint` gate does not read a doc example as a route. An
  /// empty
  /// segment is dropped the same way. Each of those addresses a **shorter
  /// route**, and this server answers an unmatched `/api/*` path with the SPA
  /// catch-all's `200 text/html` (`docs/server-api.md`, "Conventions") rather
  /// than a 404 — a success that is not one, arriving as a JSON decode failure
  /// somewhere else entirely. Curled live at v0.20.3: an empty [MediaId] on
  /// `mediaDetail` hit `/api/media` and got exactly that.
  ///
  /// So the value is refused instead of escaped. `MediaId('')` is reachable
  /// **today**: it is the models' own declared default (`media_detail.dart`,
  /// `media_summary.dart`), so any payload with a missing or null `id`
  /// produces one. Throwing here turns a request against the wrong route into
  /// a stack trace naming the value.
  static String _seg(Object value) {
    final segment = '$value';
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ArgumentError.value(
        segment,
        'value',
        'is not a usable path segment. Uri deletes an empty segment and the '
            'dot segments "." and "..", so the request would address a shorter '
            'route and the SPA catch-all would answer 200 text/html',
      );
    }
    return Uri.encodeComponent(segment);
  }

  /// `GET` — reachability and version probe. Unauthenticated.
  static const state = '/api/state';

  /// `POST` — credentials in, `filefin_session` cookie out.
  static const login = '/api/login';

  /// `POST` — drops the session server-side. Unauthenticated.
  static const logout = '/api/logout';

  /// `GET` — the current user; validates a restored session without a password.
  static const me = '/api/me';

  /// `GET` — the flat category list; the tree is assembled client-side.
  static const categories = '/api/categories';

  /// `GET` — the three home rows in one call.
  static const home = '/api/home';

  /// `GET` — `?q=&field=`. An empty `q` returns an empty array.
  static const search = '/api/search';

  /// `GET` — the curated tag vocabulary with counts.
  static const tags = '/api/tags';

  /// `GET` — direct children of a category, not the subtree.
  static String categoryMedia(CategoryId id) =>
      '/api/category/${_seg(id.value)}/media';

  /// `GET` — the full detail payload.
  static String mediaDetail(MediaId id) => '/api/media/${_seg(id.value)}';

  /// `GET` — poster bytes. `?size=` is a hint, not a contract.
  static String poster(MediaId id) => '/api/media/${_seg(id.value)}/poster';

  /// `GET` — raw bytes, a `307` to HLS, or a `415`. The server decides.
  static String file(MediaId id, FileIndex n) =>
      '/api/media/${_seg(id.value)}/file/${_seg(n.value)}';

  /// `GET` — the k-th sidecar subtitle, converted SRT to WebVTT per request.
  static String subtitle(MediaId id, FileIndex n, SubtitleIndex k) =>
      '/api/media/${_seg(id.value)}/file/${_seg(n.value)}/sub/${_seg(k.value)}';

  /// `POST` a report, `DELETE` to clear the pointer.
  static String progress(MediaId id) => '/api/media/${_seg(id.value)}/progress';

  /// `POST {"watched": bool}` keeps the pointer; `DELETE` nils it. Not the
  /// same operation — see `docs/server-api.md`.
  static String watched(MediaId id) => '/api/media/${_seg(id.value)}/watched';

  /// `POST {"favorite": bool}`.
  static String favorite(MediaId id) => '/api/media/${_seg(id.value)}/favorite';

  /// `POST {"rating": int}` — 1-10 valid, 0 clears, anything else is a `400`.
  static String rating(MediaId id) => '/api/media/${_seg(id.value)}/rating';
}

/// The `?size=` hint on a poster request.
///
/// The server serves the pre-built variant **when it exists** and otherwise
/// silently falls back to the base poster (`media.go:351`), so this is a
/// preference and the client must not assume the dimensions it gets back.
enum PosterSize {
  /// The larger variant, for a detail page.
  detail,

  /// The smaller variant, for a grid tile.
  tile;

  /// The exact token the server expects in `?size=`.
  String get wire => name;
}

/// Turns a server's base URL into the absolute URL of each endpoint.
///
/// The base may carry a path prefix (`https://host/filefin`) and may or may not
/// end in a slash; both resolve identically, because the trailing empty segment
/// `Uri` produces for `…/filefin/` is dropped before joining.
///
/// Every URL is built through the `Uri` constructor, never string
/// concatenation, so percent-encoding is the `Uri` class's problem. A
/// concatenated builder handed a value containing `/` or `?` silently addresses
/// a different route, and the failure surfaces as a 404 from somewhere else.
@immutable
class FileFinUrls {
  /// Wraps the base URL of one server.
  const FileFinUrls(this.base);

  /// The server's base URL, prefix and port included.
  final Uri base;

  /// `GET /api/state`.
  Uri get state => _resolve(ApiPaths.state);

  /// `POST /api/login`.
  Uri get login => _resolve(ApiPaths.login);

  /// `POST /api/logout`.
  Uri get logout => _resolve(ApiPaths.logout);

  /// `GET /api/me`.
  Uri get me => _resolve(ApiPaths.me);

  /// `GET /api/categories`.
  Uri get categories => _resolve(ApiPaths.categories);

  /// `GET /api/home`.
  Uri get home => _resolve(ApiPaths.home);

  /// `GET /api/tags`.
  Uri get tags => _resolve(ApiPaths.tags);

  /// `GET /api/category/{id}/media`.
  Uri categoryMedia(CategoryId id) => _resolve(ApiPaths.categoryMedia(id));

  /// `GET /api/media/{id}`.
  Uri mediaDetail(MediaId id) => _resolve(ApiPaths.mediaDetail(id));

  /// `GET /api/media/{id}/file/{n}`.
  Uri file(MediaId id, FileIndex n) => _resolve(ApiPaths.file(id, n));

  /// `GET /api/media/{id}/file/{n}/sub/{k}`.
  Uri subtitle(MediaId id, FileIndex n, SubtitleIndex k) =>
      _resolve(ApiPaths.subtitle(id, n, k));

  /// `POST` or `DELETE /api/media/{id}/progress`.
  Uri progress(MediaId id) => _resolve(ApiPaths.progress(id));

  /// `POST` or `DELETE /api/media/{id}/watched`.
  Uri watched(MediaId id) => _resolve(ApiPaths.watched(id));

  /// `POST /api/media/{id}/favorite`.
  Uri favorite(MediaId id) => _resolve(ApiPaths.favorite(id));

  /// `POST /api/media/{id}/rating`.
  Uri rating(MediaId id) => _resolve(ApiPaths.rating(id));

  /// `GET /api/media/{id}/poster`, with the `?size=` hint only when asked for.
  ///
  /// Absent and unrecognised both serve the base poster, so omitting the
  /// parameter entirely rather than sending an empty one keeps the request
  /// honest about what it wants.
  Uri poster(MediaId id, {PosterSize? size}) => _resolve(
    ApiPaths.poster(id),
    size == null ? null : {'size': size.wire},
  );

  /// `GET /api/search?q=&field=`.
  ///
  /// Both parameters are always sent. `field` defaults to `all` upstream when
  /// absent, but sending it makes the request say what it means, and an unknown
  /// value degrades silently rather than erroring.
  Uri search(String query, {SearchField field = SearchField.all}) =>
      _resolve(ApiPaths.search, {'q': query, 'field': field.wire});

  /// Joins [path] onto [base]'s own path and returns an absolute URL.
  ///
  /// Built with the `Uri` constructor rather than `base.replace` so that the
  /// base's query and fragment are dropped rather than inherited: a saved
  /// server URL carrying `?theme=dark` must not append itself to every request.
  ///
  /// `port` is passed only when [base] wrote one: `base.port` reports the
  /// scheme's default otherwise, which turns `https://h` into `https://h:443`.
  ///
  /// Each segment is decoded here and re-encoded by `Uri`. [ApiPaths._seg]
  /// escaped it so a `/` inside a parameter could not split into an extra
  /// segment, and this is where that escaping is handed back.
  ///
  /// **The two halves filter differently, deliberately.** The base half drops
  /// every empty segment, because `https://h/filefin/` and `https://h/filefin`
  /// must resolve identically. The path half drops exactly one — `skip(1)`, the
  /// empty string before the leading `/` that every [ApiPaths] literal starts
  /// with, asserted in `urls_test.dart`. It used to filter empties everywhere,
  /// which quietly did [ApiPaths._seg]'s job for it: an empty id vanished and
  /// the URL addressed a shorter route that the SPA catch-all answers
  /// `200 text/html`. One guard that refuses beats two mechanisms that
  /// disagree, so an empty segment that ever gets past `_seg` must now survive
  /// into a doubled slash — a visible 404 — rather than disappear.
  Uri _resolve(String path, [Map<String, String>? query]) => Uri(
    scheme: base.scheme,
    userInfo: base.userInfo,
    host: base.host,
    port: base.hasPort ? base.port : null,
    pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').skip(1).map(Uri.decodeComponent),
    ],
    queryParameters: query,
  );

  @override
  bool operator ==(Object other) => other is FileFinUrls && other.base == base;

  @override
  int get hashCode => base.hashCode;

  @override
  String toString() => 'FileFinUrls($base)';
}
