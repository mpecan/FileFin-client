import 'package:filefin_core/src/models/media_summary.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_rows.freezed.dart';
part 'home_rows.g.dart';

/// `GET /api/home` — three `MediaSummary[]` rows in one call (`media.go`,
/// anonymous struct at `:237-241`), newest first by the per-user `updated`
/// stamp.
///
/// The wire key for the first row is **`continue`**, a Dart reserved word, so
/// the field is named [continueRow] and pinned to the wire name by `@JsonKey`.
/// Getting this wrong does not fail to compile — it silently produces an empty
/// row, which looks exactly like a user who has watched nothing.
@freezed
abstract class HomeRows with _$HomeRows {
  /// The three home rows, each defaulting to an empty list rather than null.
  const factory HomeRows({
    @JsonKey(name: 'continue')
    @Default(<MediaSummary>[])
    List<MediaSummary> continueRow,
    @Default(<MediaSummary>[]) List<MediaSummary> favorites,
    @Default(<MediaSummary>[]) List<MediaSummary> completed,
  }) = _HomeRows;

  /// Decodes a payload from the server, tolerating unknown keys.
  factory HomeRows.fromJson(Map<String, Object?> json) =>
      _$HomeRowsFromJson(json);
}
