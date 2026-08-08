import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/json_converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';
part 'category.g.dart';

/// One row of `GET /api/categories` — a flat list, DTO `library.go:27-42`.
///
/// The tree is assembled client-side from [parentId]. `parentId == 0` means
/// **top level**, not "absent", which is why it is a `CategoryId` with a
/// default rather than a nullable.
///
/// [media] and [files] are cache annotations: when the cache is unavailable the
/// listing still returns with both at 0 (`library.go:73-81`), so a client
/// cannot tell "empty category" from "cache down" by these counts alone.
@freezed
abstract class Category with _$Category {
  /// One category row, with every field defaulted (§8).
  const factory Category({
    @CategoryIdConverter() @Default(CategoryId(0)) CategoryId id,
    @Default('') String name,
    @Default('') String leaf,
    @Default('') String alias,
    @CategoryIdConverter() @Default(CategoryId(0)) CategoryId parentId,
    @Default(false) bool otherMedia,
    @Default(0) int position,
    @Default(false) bool empty,
    @Default(0) int media,
    @Default(0) int files,
    @Default('') String kind,
    @Default(0) int learned,
  }) = _Category;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory Category.fromJson(Map<String, Object?> json) =>
      _$CategoryFromJson(json);
}
