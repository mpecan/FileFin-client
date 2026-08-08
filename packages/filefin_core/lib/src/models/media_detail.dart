import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_detail.freezed.dart';
part 'media_detail.g.dart';

/// One sidecar subtitle track — upstream `subtitleInfo`, `media.go:30-34`.
///
/// Sidecars only. Embedded tracks are externalised at import time rather than
/// at play time, so this list is everything the API can offer. (libmpv renders
/// embedded tracks itself on the direct-play path; surfacing those is deferred,
/// SPEC.md §11.)
@freezed
abstract class SubtitleInfo with _$SubtitleInfo {
  /// One sidecar track, every field defaulted (§8).
  const factory SubtitleInfo({
    @SubtitleIndexConverter() @Default(SubtitleIndex(0)) SubtitleIndex index,
    @Default('') String lang,
    @Default('') String label,
  }) = _SubtitleInfo;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory SubtitleInfo.fromJson(Map<String, Object?> json) =>
      _$SubtitleInfoFromJson(json);
}

/// One playable file inside a media folder — upstream `fileInfo`,
/// `media.go:36-49`.
///
/// Two fields matter disproportionately:
///
/// - [transcode] is **the server's verdict** that this file is not
///   browser-native, computed by the same function that decides what
///   `GET .../file/{n}` will answer. `decide()` uses it and must never
///   reimplement `transcode.DirectPlayable`; a second copy would drift from a
///   decision the server has already made and told us.
/// - [size] is the only bandwidth signal the API gives us, and therefore the
///   entire basis of the metered-connection guard (F13).
///
/// [season] and [episode] are **0** for a single-file item, not null.
@freezed
abstract class FileInfo with _$FileInfo {
  /// One file, every field defaulted (§8).
  const factory FileInfo({
    @FileIndexConverter() @Default(FileIndex(0)) FileIndex index,
    @Default('') String name,
    @Default('') String path,
    @Default(0) int size,
    @Default(0) int season,
    @Default(0) int episode,
    @Default('') String ext,
    @Default(false) bool transcode,
    @Default(false) bool watched,
    @Default(<SubtitleInfo>[]) List<SubtitleInfo> subtitles,
  }) = _FileInfo;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory FileInfo.fromJson(Map<String, Object?> json) =>
      _$FileInfoFromJson(json);
}

/// A display label and its value — upstream `pair`, `media.go:51-54`.
///
/// **[key] is a display label, not a stable identifier.** `orderedPairs`
/// (`media.go:101`) maps known `meta.json` keys through
/// `metadataLabels`/`ratingLabels` — `release` becomes `Released`, `imdb`
/// becomes `IMDb` — and any unlisted key falls through in sorted order under
/// its raw name. So the client renders these and never keys off them. The
/// captured fixture carries a `customKey` entry to keep that honest.
@freezed
abstract class MetaPair with _$MetaPair {
  /// One display label and its value, both defaulted (§8).
  const factory MetaPair({
    @Default('') String key,
    @Default('') String value,
  }) = _MetaPair;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory MetaPair.fromJson(Map<String, Object?> json) =>
      _$MetaPairFromJson(json);
}

/// `GET /api/media/{id}` — the detail payload, upstream `mediaDetail`,
/// `media.go:56-75`.
///
/// Every list is initialised to an empty slice upstream (`media.go:273-278`) so
/// they arrive as `[]` and never `null`. They default here anyway: the
/// guarantee is upstream's, not ours (§8).
///
/// A missing `meta.json` is non-fatal (`media.go:282`) — the cache row still
/// supplies id, title, year, description, plot and files, and the rich blocks
/// come back empty. So an item with no metadata is normal, not an error.
///
/// [continueIndex] and [continueSeconds] are the **derived** resume view, not
/// the stored pointer: a pointer whose ref no longer matches any file reads
/// here as `0`/`0` — and so does a real pointer at the very start of a
/// single-file item. `WatchState.fromDetail` reads `0`/`0` as "no pointer",
/// which is right for the first case and wrong for the second, and the error
/// it leaves **persists** until this payload is fetched again. Re-read the
/// detail after a report that crosses 90% of a single-file item;
/// `WatchState.fromDetail` sets out why and what it costs.
///
/// [rating] is passed through exactly as the server sent it, including values
/// the server's own write path would reject — it clamps on write, not on read
/// (`media.go:425`). `WatchState.fromDetail` is where that is normalised.
@freezed
abstract class MediaDetail with _$MediaDetail {
  /// The full detail payload, every field defaulted (§8).
  const factory MediaDetail({
    @MediaIdConverter() @Default(MediaId('')) MediaId id,
    @Default('') String title,
    @Default(0) int year,
    @Default('') String description,
    @Default('') String plot,
    @Default(false) bool hasPoster,
    @Default(<FileInfo>[]) List<FileInfo> files,
    @Default(<MetaPair>[]) List<MetaPair> metadata,
    @Default(<MetaPair>[]) List<MetaPair> ratings,
    @Default(<MetaPair>[]) List<MetaPair> technical,
    @Default(<String>[]) List<String> actors,
    @Default(<String>[]) List<String> genres,
    @Default(<String>[]) List<String> tags,
    @Default(false) bool watched,
    @Default(false) bool favorite,
    @Default(0) int rating,
    @Default(0) int continueIndex,
    @Default(0) int continueSeconds,
  }) = _MediaDetail;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory MediaDetail.fromJson(Map<String, Object?> json) =>
      _$MediaDetailFromJson(json);
}
