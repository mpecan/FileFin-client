import 'dart:ui' as ui;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What Flutter's `ImageCache` keys a poster on.
///
/// **`ServerId` is in the key and that is not decoration.** Two saved servers
/// can hand out the same `MediaId` — it is `sha1(category + "/" + folder)[:12]`
///, which says nothing about which machine produced it — so a
/// key of `(MediaId, PosterSize)` alone would show one server's artwork on the
/// other's item, silently and only for people with two servers.
@immutable
class PosterKey {
  /// The cache key for [media] on [server] at [size].
  const PosterKey(this.server, this.media, this.size);

  /// Which saved server.
  final ServerId server;

  /// Which item.
  final MediaId media;

  /// Which variant was asked for, if any.
  final PosterSize? size;

  @override
  bool operator ==(Object other) =>
      other is PosterKey &&
      other.server == server &&
      other.media == media &&
      other.size == size;

  @override
  int get hashCode => Object.hash(server, media, size);

  @override
  String toString() => 'PosterKey(${server.value}, ${media.value}, $size)';
}

/// Fetches a poster **through `FileFinClient`**, never through `Image.network`.
///
/// The poster route sits behind `s.auth`, so `Image.network` cannot work: it
/// builds its own `HttpClient` with no cookie jar, no 401 retry and no pin
/// pinning, and the request would simply 401. `just constitution`'s
/// `app_no_raw_http` check refuses the shortcut for exactly that reason.
///
/// Being an `ImageProvider` rather than a bare fetch is what puts posters in
/// Flutter's `ImageCache` — 1000 entries / 100 MB by default — which is what
/// bounds memory over a 5000-item category. 's `cache/posters/` disk cache is
/// deliberately NOT here: large libraries need posters lazy, not durable, and a
/// disk cache arrives with a milestone that measures a need for one.
class PosterImageProvider extends ImageProvider<PosterKey> {
  /// Fetches [media]'s poster through [api], cancelling with [cancelToken].
  const PosterImageProvider({
    required this.api,
    required this.media,
    this.size,
    this.cancelToken,
  });

  /// The port the bytes come from.
  final LibraryApi api;

  /// Which item's poster.
  final MediaId media;

  /// The `?size=` hint. A hint, not a contract.
  final PosterSize? size;

  /// The owning tile's token, so a scrolled-away request stops.
  final CancelToken? cancelToken;

  @override
  Future<PosterKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(PosterKey(api.server, media, size));

  @override
  ImageStreamCompleter loadImage(PosterKey key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: '$key',
      );

  /// Throws when there is no poster, and that is the interface's own idiom.
  ///
  /// `posterBytes` returns null for the 404 that means "this item has no
  /// artwork", which is normal. An `ImageProvider` has no way to say "nothing,
  /// and that is fine", so the absence becomes a failure here and
  /// `PosterTile` renders its title placeholder rather than an error.
  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await api.posterBytes(
      media,
      size: size,
      cancelToken: cancelToken,
    );
    if (bytes == null || bytes.isEmpty) {
      throw StateError('no poster for ${media.value}');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }
}
