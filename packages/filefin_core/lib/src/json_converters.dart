import 'package:filefin_core/src/ids.dart';
import 'package:json_annotation/json_annotation.dart';

/// `json_serializable` does not understand extension types, so a
/// `JsonConverter` is how a field keeps its wrapper type (§7) while staying a
/// plain string or number on the wire.
///
/// Each is `const`: the generator inlines `const XConverter().fromJson`, which
/// only compiles for a const constructor.
///
/// **None of these validates**, deliberately — §8 makes tolerating an
/// unexpected value our job, and a decoder that throws turns one odd item into
/// a blank screen.
class MediaIdConverter extends JsonConverter<MediaId, String> {
  /// The single const instance a `@MediaIdConverter()` annotation names.
  const MediaIdConverter();

  @override
  MediaId fromJson(String json) => MediaId(json);

  @override
  String toJson(MediaId object) => object.value;
}

/// `id` and `parentId` on a category. `0` is the top-level sentinel upstream
/// writes, not a missing value, so it survives the round trip unchanged.
class CategoryIdConverter extends JsonConverter<CategoryId, int> {
  /// The single const instance a `@CategoryIdConverter()` annotation names.
  const CategoryIdConverter();

  @override
  CategoryId fromJson(int json) => CategoryId(json);

  @override
  int toJson(CategoryId object) => object.value;
}

/// `files[].index`, and the `{n}` every playback path is addressed by.
class FileIndexConverter extends JsonConverter<FileIndex, int> {
  /// The single const instance a `@FileIndexConverter()` annotation names.
  const FileIndexConverter();

  @override
  FileIndex fromJson(int json) => FileIndex(json);

  @override
  int toJson(FileIndex object) => object.value;
}

/// `subtitles[].index`, and the `{k}` in the subtitle path.
class SubtitleIndexConverter extends JsonConverter<SubtitleIndex, int> {
  /// The single const instance a `@SubtitleIndexConverter()` annotation names.
  const SubtitleIndexConverter();

  @override
  SubtitleIndex fromJson(int json) => SubtitleIndex(json);

  @override
  int toJson(SubtitleIndex object) => object.value;
}
