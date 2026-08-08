import 'dart:typed_data';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';

/// Everything the UI is allowed to ask a server for.
///
/// **A port, and the reason is testability rather than tidiness.** A widget
/// test that wants to see the error panel has to make a request fail; against
/// `FileFinClient` that means standing up a socket and arranging a status code,
/// and inside `testWidgets` it also means `tester.runAsync` because a real
/// socket's callback never fires under `FakeAsync` (measured at M3.0). Against
/// this interface it means a two-line fake that throws.
///
/// **`abstract base class`, following `SecretStore`'s reasoning.** `base`
/// forces subtypes to `extend` rather than `implement`, so a new method here is
/// a compile error in every implementation instead of something an
/// `implements` clause silently satisfies with a stub.
///
/// Every method takes a `CancelToken` (NF5). None of them is optional in
/// practice: a poster request that outlives its tile is the difference between
/// a grid that scrolls and one that queues five thousand requests.
abstract base class LibraryApi {
  /// Allows implementations to be `const`.
  const LibraryApi();

  /// Which saved server this talks to.
  ///
  /// Read by the poster image provider's cache key: two servers can hand out
  /// the same media id, and a key that ignored this would show one server's
  /// artwork on the other's item.
  ServerId get server;

  /// `GET /api/state` — is there a FileFin server at this address (F1)?
  Future<ProbeResult> probeServer({CancelToken? cancelToken});

  /// `POST /api/login` — signs in and stores the session and password (F2).
  Future<AuthResult> login(Credentials credentials);

  /// `GET /api/categories` — the flat list, for `buildCategoryTree`.
  Future<List<Category>> categories({CancelToken? cancelToken});

  /// `GET /api/category/{id}/media` — direct children, not the subtree.
  Future<List<MediaSummary>> categoryMedia(
    CategoryId id, {
    CancelToken? cancelToken,
  });

  /// `GET /api/media/{id}` — the full detail payload.
  Future<MediaDetail> mediaDetail(MediaId id, {CancelToken? cancelToken});

  /// `GET /api/media/{id}/poster` — bytes, or null when there is no poster.
  Future<Uint8List?> posterBytes(
    MediaId id, {
    PosterSize? size,
    CancelToken? cancelToken,
  });

  /// Releases the sockets behind this API.
  void close();
}

/// The real implementation: a thin delegation to one [FileFinClient].
///
/// Thin on purpose. Every decision that could live here — what a 401 means,
/// what a 404 on the poster route means, which errors exist — already lives in
/// `filefin_api`, and a second layer with opinions would be a second place for
/// them to disagree.
final class FileFinLibraryApi extends LibraryApi {
  /// Wraps one [FileFinClient].
  const FileFinLibraryApi(this._client);

  final FileFinClient _client;

  @override
  ServerId get server => _client.server;

  @override
  Future<ProbeResult> probeServer({CancelToken? cancelToken}) =>
      _client.probeServer(cancelToken: cancelToken);

  @override
  Future<AuthResult> login(Credentials credentials) =>
      _client.login(credentials);

  @override
  Future<List<Category>> categories({CancelToken? cancelToken}) =>
      _client.categories(cancelToken: cancelToken);

  @override
  Future<List<MediaSummary>> categoryMedia(
    CategoryId id, {
    CancelToken? cancelToken,
  }) => _client.categoryMedia(id, cancelToken: cancelToken);

  @override
  Future<MediaDetail> mediaDetail(MediaId id, {CancelToken? cancelToken}) =>
      _client.mediaDetail(id, cancelToken: cancelToken);

  @override
  Future<Uint8List?> posterBytes(
    MediaId id, {
    PosterSize? size,
    CancelToken? cancelToken,
  }) => _client.posterBytes(id, size: size, cancelToken: cancelToken);

  @override
  void close() => _client.close();
}
