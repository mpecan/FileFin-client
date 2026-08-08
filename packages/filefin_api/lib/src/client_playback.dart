part of 'client.dart';

/// Everything `FileFinClient` does for the player, in a part file.
///
/// A `part` rather than a second class, so it still reaches `_dio`, `_uri`,
/// `_sendJson` and `_asOurs` — one error vocabulary, one URL guard, one place
/// a 401 means something. The split is `file-size`'s doing: `client.dart`
/// crossed the 400-line soft warning when these landed, and a gate warning may
/// fall or hold and never rise. Splitting by subject keeps both halves
/// readable, which is what `errors.dart` and `errors_certificates.dart`
/// already do for the same reason.
extension FileFinClientPlayback on FileFinClient {
  /// `POST /api/media/{id}/progress` — one playback report (F9), `204`.
  ///
  /// `async` for the same reason as [categoryMedia]: a rejected identifier
  /// arrives as a failed Future rather than as a synchronous throw, and this
  /// one is called from a position tick where a synchronous throw would escape
  /// into the player's own stream handler.
  ///
  /// A `400` is [BadRequest] and means the file list changed under us
  /// (`bad file index`, `media.go:511`). It is deliberately **not** retryable:
  /// the same body would be rejected on every subsequent tick.
  Future<void> postProgress(
    MediaId id,
    ProgressReport report, {
    CancelToken? cancelToken,
  }) async => _sendJson(
    _uri(() => urls.progress(id), 'media id'),
    // Written out rather than generated. `ProgressReport` has no `toJson` —
    // it is a client-side type the engine folds, not a wire model — and the
    // four field names are the server's (`media.go:503`), so spelling them
    // here is what keeps `just it` able to catch a rename.
    {
      'file': report.file.value,
      'position': report.position,
      'duration': report.duration,
      'event': report.event.wire,
    },
    cancelToken: cancelToken,
  );

  /// `GET .../file/{n}/sub/{k}` — the k-th sidecar, converted SRT→WebVTT.
  ///
  /// **Fetched through this client on purpose, rather than handed to libmpv as
  /// a URL.** The route sits behind `s.auth`, so a `sub-add` from libmpv would
  /// use its own unverified HTTP with no cookie jar, no F3 retry and no pin.
  /// Reading the text here and passing it to `SubtitleTrack.data` keeps the
  /// authenticated path for the one part of playback that can use it.
  ///
  /// The response is `text/vtt; charset=utf-8` (measured live at v0.20.3), so
  /// this must not go through the JSON media-type check — but an HTML body
  /// still means the SPA catch-all answered and is refused.
  Future<String> subtitleText(
    MediaId id,
    FileIndex file,
    SubtitleIndex subtitle, {
    CancelToken? cancelToken,
  }) async {
    final url = _uri(() => urls.subtitle(id, file, subtitle), 'media id');
    try {
      final response = await _dio.getUri<String>(
        url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain),
      );
      FileFinClient._refuseHtml(response.headers, url);
      return response.data ?? '';
    } on DioException catch (e) {
      throw _asOurs(e, url);
    }
  }

  /// The absolute URL libmpv should open for [file] of [id].
  ///
  /// Through [_uri], so a media id the server sent that cannot go in a path is
  /// a [MalformedIdentifier] rather than a request against a shorter route the
  /// SPA catch-all answers `200 text/html`.
  Uri fileUrl(MediaId id, FileIndex file) =>
      _uri(() => urls.file(id, file), 'media id');

  /// The absolute URL of one sidecar subtitle, for the same reason.
  Uri subtitleUrl(MediaId id, FileIndex file, SubtitleIndex subtitle) =>
      _uri(() => urls.subtitle(id, file, subtitle), 'media id');

  /// The headers libmpv must carry, after proving the session is alive.
  ///
  /// **The `me()` first is the whole point, not a formality.** libmpv cannot
  /// see a status code: a 401 arrives as "failed to open" and nothing else, so
  /// a dead session would look exactly like a missing file. Making one
  /// authenticated call through this package immediately before the open means
  /// F3 has already renewed and the cookie handed over is the renewed one.
  ///
  /// A `200` with no cookie in the jar is [SessionExpired] rather than an empty
  /// header: handing libmpv `Cookie: filefin_session=` produces a 401 inside
  /// mpv, which surfaces as the same unexplained failure.
  Future<PlaybackSessionHeaders> playbackHeaders({
    CancelToken? cancelToken,
  }) async {
    await me(cancelToken: cancelToken);
    final cookie = await sessions.sessionCookie();
    if (cookie == null) throw SessionExpired(urls.me);
    return PlaybackSessionHeaders({
      'Cookie': '$sessionCookieName=$cookie',
    });
  }

  /// What libmpv's own connection to this server would be able to verify.
  ///
  /// It reads this client's own configuration and asks nothing: the scheme
  /// says whether TLS is in play at all, and a pin's existence says whether
  /// the certificate is one only *we* trust. `decide()` turns that into D10's
  /// refusal.
  ///
  /// A pin over plain `http://` is still [PlaybackTransport.plainHttp] —
  /// there is no handshake to pin, so reporting otherwise would refuse
  /// playback for a protection that was never in effect.
  PlaybackTransport playbackTransport() {
    if (urls.base.scheme != 'https') return PlaybackTransport.plainHttp;
    return pinner?.pin == null
        ? PlaybackTransport.osTrustedTls
        : PlaybackTransport.pinnedTls;
  }
}
