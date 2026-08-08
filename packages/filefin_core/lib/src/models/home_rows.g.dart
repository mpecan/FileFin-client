// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_rows.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_HomeRows _$HomeRowsFromJson(Map<String, dynamic> json) => _HomeRows(
  continueRow:
      (json['continue'] as List<dynamic>?)
          ?.map((e) => MediaSummary.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MediaSummary>[],
  favorites:
      (json['favorites'] as List<dynamic>?)
          ?.map((e) => MediaSummary.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MediaSummary>[],
  completed:
      (json['completed'] as List<dynamic>?)
          ?.map((e) => MediaSummary.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MediaSummary>[],
);

Map<String, dynamic> _$HomeRowsToJson(_HomeRows instance) => <String, dynamic>{
  'continue': instance.continueRow.map((e) => e.toJson()).toList(),
  'favorites': instance.favorites.map((e) => e.toJson()).toList(),
  'completed': instance.completed.map((e) => e.toJson()).toList(),
};
