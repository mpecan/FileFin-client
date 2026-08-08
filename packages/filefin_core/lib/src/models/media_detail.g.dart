// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SubtitleInfo _$SubtitleInfoFromJson(Map<String, dynamic> json) =>
    _SubtitleInfo(
      index: json['index'] == null
          ? const SubtitleIndex(0)
          : const SubtitleIndexConverter().fromJson(
              (json['index'] as num).toInt(),
            ),
      lang: json['lang'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );

Map<String, dynamic> _$SubtitleInfoToJson(_SubtitleInfo instance) =>
    <String, dynamic>{
      'index': const SubtitleIndexConverter().toJson(instance.index),
      'lang': instance.lang,
      'label': instance.label,
    };

_FileInfo _$FileInfoFromJson(Map<String, dynamic> json) => _FileInfo(
  index: json['index'] == null
      ? const FileIndex(0)
      : const FileIndexConverter().fromJson((json['index'] as num).toInt()),
  name: json['name'] as String? ?? '',
  path: json['path'] as String? ?? '',
  size: (json['size'] as num?)?.toInt() ?? 0,
  season: (json['season'] as num?)?.toInt() ?? 0,
  episode: (json['episode'] as num?)?.toInt() ?? 0,
  ext: json['ext'] as String? ?? '',
  transcode: json['transcode'] as bool? ?? false,
  watched: json['watched'] as bool? ?? false,
  subtitles:
      (json['subtitles'] as List<dynamic>?)
          ?.map((e) => SubtitleInfo.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <SubtitleInfo>[],
);

Map<String, dynamic> _$FileInfoToJson(_FileInfo instance) => <String, dynamic>{
  'index': const FileIndexConverter().toJson(instance.index),
  'name': instance.name,
  'path': instance.path,
  'size': instance.size,
  'season': instance.season,
  'episode': instance.episode,
  'ext': instance.ext,
  'transcode': instance.transcode,
  'watched': instance.watched,
  'subtitles': instance.subtitles.map((e) => e.toJson()).toList(),
};

_MetaPair _$MetaPairFromJson(Map<String, dynamic> json) => _MetaPair(
  key: json['key'] as String? ?? '',
  value: json['value'] as String? ?? '',
);

Map<String, dynamic> _$MetaPairToJson(_MetaPair instance) => <String, dynamic>{
  'key': instance.key,
  'value': instance.value,
};

_MediaDetail _$MediaDetailFromJson(Map<String, dynamic> json) => _MediaDetail(
  id: json['id'] == null
      ? const MediaId('')
      : const MediaIdConverter().fromJson(json['id'] as String),
  title: json['title'] as String? ?? '',
  year: (json['year'] as num?)?.toInt() ?? 0,
  description: json['description'] as String? ?? '',
  plot: json['plot'] as String? ?? '',
  hasPoster: json['hasPoster'] as bool? ?? false,
  files:
      (json['files'] as List<dynamic>?)
          ?.map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <FileInfo>[],
  metadata:
      (json['metadata'] as List<dynamic>?)
          ?.map((e) => MetaPair.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MetaPair>[],
  ratings:
      (json['ratings'] as List<dynamic>?)
          ?.map((e) => MetaPair.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MetaPair>[],
  technical:
      (json['technical'] as List<dynamic>?)
          ?.map((e) => MetaPair.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MetaPair>[],
  actors:
      (json['actors'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  genres:
      (json['genres'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  watched: json['watched'] as bool? ?? false,
  favorite: json['favorite'] as bool? ?? false,
  rating: (json['rating'] as num?)?.toInt() ?? 0,
  continueIndex: (json['continueIndex'] as num?)?.toInt() ?? 0,
  continueSeconds: (json['continueSeconds'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$MediaDetailToJson(_MediaDetail instance) =>
    <String, dynamic>{
      'id': const MediaIdConverter().toJson(instance.id),
      'title': instance.title,
      'year': instance.year,
      'description': instance.description,
      'plot': instance.plot,
      'hasPoster': instance.hasPoster,
      'files': instance.files.map((e) => e.toJson()).toList(),
      'metadata': instance.metadata.map((e) => e.toJson()).toList(),
      'ratings': instance.ratings.map((e) => e.toJson()).toList(),
      'technical': instance.technical.map((e) => e.toJson()).toList(),
      'actors': instance.actors,
      'genres': instance.genres,
      'tags': instance.tags,
      'watched': instance.watched,
      'favorite': instance.favorite,
      'rating': instance.rating,
      'continueIndex': instance.continueIndex,
      'continueSeconds': instance.continueSeconds,
    };
