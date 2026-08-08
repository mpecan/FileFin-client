// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MediaSummary _$MediaSummaryFromJson(Map<String, dynamic> json) =>
    _MediaSummary(
      id: json['id'] == null
          ? const MediaId('')
          : const MediaIdConverter().fromJson(json['id'] as String),
      title: json['title'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      hasPoster: json['hasPoster'] as bool? ?? false,
      watched: json['watched'] as bool? ?? false,
    );

Map<String, dynamic> _$MediaSummaryToJson(_MediaSummary instance) =>
    <String, dynamic>{
      'id': const MediaIdConverter().toJson(instance.id),
      'title': instance.title,
      'year': instance.year,
      'hasPoster': instance.hasPoster,
      'watched': instance.watched,
    };
