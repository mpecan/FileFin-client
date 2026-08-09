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

  /// `GET /api/home` — the continue / favourites / completed rows (F6).
  ///
  /// **Refetched after a write, never predicted.** The rows come from the
  /// `user_state` mirror rather than from `meta.json` (`media.go:227`), the
  /// mirror upsert is best-effort, and the bucket order is `updated DESC` where
  /// `updated` is re-stamped by *every* write — so setting a rating re-orders
  /// the continue row (M6.0/E-3). None of that is derivable from what a client
  /// holds.
  Future<HomeRows> home({CancelToken? cancelToken});

  /// `GET /api/search?q=&field=` — the field selector's results (F5).
  Future<List<MediaSummary>> search(
    String query, {
    SearchField field,
    CancelToken? cancelToken,
  });

  /// `POST /api/media/{id}/favorite` (F10).
  Future<void> setFavorite(
    MediaId id, {
    required bool favorite,
    CancelToken? cancelToken,
  });

  /// `POST /api/media/{id}/rating` — 1-10, 0 clears; anything else throws (F10).
  Future<void> setRating(
    MediaId id, {
    required int rating,
    CancelToken? cancelToken,
  });

  /// `POST /api/media/{id}/watched` — sets or clears the flag and **keeps the
  /// resume pointer** (F10).
  ///
  /// Four methods rather than one with a boolean, and this pair is why. See
  /// [clearWatched].
  Future<void> setWatched(
    MediaId id, {
    required bool watched,
    CancelToken? cancelToken,
  });

  /// `DELETE /api/media/{id}/watched` — clears the flag **and nils the
  /// pointer** (F10).
  ///
  /// Measured against v0.20.3 at M6.0/E-5: after `setWatched(watched: false)`
  /// the item is back in `continue` with its position intact; after this it is
  /// in no home row at all and the position is gone. Collapsing the two into
  /// one boolean would erase a resume position every time a user un-watches
  /// something.
  Future<void> clearWatched(MediaId id, {CancelToken? cancelToken});

  /// `GET /api/media/{id}/poster` — bytes, or null when there is no poster.
  Future<Uint8List?> posterBytes(
    MediaId id, {
    PosterSize? size,
    CancelToken? cancelToken,
  });

  /// `GET /api/me` — the current user; proves the session is alive.
  ///
  /// Playback needs it for a reason browsing does not: libmpv cannot see a
  /// status code, so a mid-playback failure has to be classified by asking the
  /// layer that can.
  Future<AuthResult> me({CancelToken? cancelToken});

  /// `POST /api/media/{id}/progress` — one playback report (F9).
  Future<void> postProgress(
    MediaId id,
    ProgressReport report, {
    CancelToken? cancelToken,
  });

  /// `GET .../file/{n}/sub/{k}` — one sidecar, as WebVTT text.
  Future<String> subtitleText(
    MediaId id,
    FileIndex file,
    SubtitleIndex subtitle, {
    CancelToken? cancelToken,
  });

  /// The headers libmpv must carry, after proving the session is alive.
  Future<PlaybackSessionHeaders> playbackHeaders({CancelToken? cancelToken});

  /// `HEAD .../file/{n}` — refuses before the engine opens, or returns (F12).
  ///
  /// Throws `TranscodingDisabled` for the `415` libmpv could only report as
  /// "failed to open". Returns for `2xx` and for the `307` to HLS alike.
  Future<void> requirePlayable(
    MediaId id,
    FileIndex file, {
    CancelToken? cancelToken,
  });

  /// The absolute URL libmpv should open for one file.
  Uri fileUrl(MediaId id, FileIndex file);

  /// The absolute URL of one sidecar subtitle.
  Uri subtitleUrl(MediaId id, FileIndex file, SubtitleIndex subtitle);

  /// What libmpv's own connection to this server would be able to verify (D10).
  PlaybackTransport playbackTransport();

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
  Future<AuthResult> me({CancelToken? cancelToken}) =>
      _client.me(cancelToken: cancelToken);

  @override
  Future<void> postProgress(
    MediaId id,
    ProgressReport report, {
    CancelToken? cancelToken,
  }) => _client.postProgress(id, report, cancelToken: cancelToken);

  @override
  Future<String> subtitleText(
    MediaId id,
    FileIndex file,
    SubtitleIndex subtitle, {
    CancelToken? cancelToken,
  }) => _client.subtitleText(id, file, subtitle, cancelToken: cancelToken);

  @override
  Future<PlaybackSessionHeaders> playbackHeaders({CancelToken? cancelToken}) =>
      _client.playbackHeaders(cancelToken: cancelToken);

  @override
  Future<void> requirePlayable(
    MediaId id,
    FileIndex file, {
    CancelToken? cancelToken,
  }) => _client.requirePlayable(id, file, cancelToken: cancelToken);

  @override
  Uri fileUrl(MediaId id, FileIndex file) => _client.fileUrl(id, file);

  @override
  Uri subtitleUrl(MediaId id, FileIndex file, SubtitleIndex subtitle) =>
      _client.subtitleUrl(id, file, subtitle);

  @override
  PlaybackTransport playbackTransport() => _client.playbackTransport();

  @override
  Future<HomeRows> home({CancelToken? cancelToken}) =>
      _client.home(cancelToken: cancelToken);

  @override
  Future<List<MediaSummary>> search(
    String query, {
    SearchField field = SearchField.all,
    CancelToken? cancelToken,
  }) => _client.search(query, field: field, cancelToken: cancelToken);

  @override
  Future<void> setFavorite(
    MediaId id, {
    required bool favorite,
    CancelToken? cancelToken,
  }) => _client.setFavorite(id, favorite: favorite, cancelToken: cancelToken);

  @override
  Future<void> setRating(
    MediaId id, {
    required int rating,
    CancelToken? cancelToken,
  }) => _client.setRating(id, rating: rating, cancelToken: cancelToken);

  @override
  Future<void> setWatched(
    MediaId id, {
    required bool watched,
    CancelToken? cancelToken,
  }) => _client.setWatched(id, watched: watched, cancelToken: cancelToken);

  @override
  Future<void> clearWatched(MediaId id, {CancelToken? cancelToken}) =>
      _client.clearWatched(id, cancelToken: cancelToken);

  @override
  void close() => _client.close();
}
