import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_summary.freezed.dart';
part 'media_summary.g.dart';

/// The list element every browsing endpoint returns — `db/media_query.go`.
///
/// Category listings, the home rows and search all answer with an array of
/// these, ordered year then title. [watched] is
/// per-user, overlaid from the `user_state` mirror.
///
/// `FolderPath` exists upstream but is `json:"-"` and never reaches the wire.
@freezed
abstract class MediaSummary with _$MediaSummary {
  /// One library item as it appears in a list, every field defaulted.
  const factory MediaSummary({
    @MediaIdConverter() @Default(MediaId('')) MediaId id,
    @Default('') String title,
    @Default(0) int year,
    @Default(false) bool hasPoster,
    @Default(false) bool watched,
  }) = _MediaSummary;

  /// Decodes a payload from the server, tolerating unknown keys.
  factory MediaSummary.fromJson(Map<String, Object?> json) =>
      _$MediaSummaryFromJson(json);
}
