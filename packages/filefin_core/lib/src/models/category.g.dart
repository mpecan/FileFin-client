// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Category _$CategoryFromJson(Map<String, dynamic> json) => _Category(
  id: json['id'] == null
      ? const CategoryId(0)
      : const CategoryIdConverter().fromJson((json['id'] as num).toInt()),
  name: json['name'] as String? ?? '',
  leaf: json['leaf'] as String? ?? '',
  alias: json['alias'] as String? ?? '',
  parentId: json['parentId'] == null
      ? const CategoryId(0)
      : const CategoryIdConverter().fromJson((json['parentId'] as num).toInt()),
  otherMedia: json['otherMedia'] as bool? ?? false,
  position: (json['position'] as num?)?.toInt() ?? 0,
  empty: json['empty'] as bool? ?? false,
  media: (json['media'] as num?)?.toInt() ?? 0,
  files: (json['files'] as num?)?.toInt() ?? 0,
  kind: json['kind'] as String? ?? '',
  learned: (json['learned'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$CategoryToJson(_Category instance) => <String, dynamic>{
  'id': const CategoryIdConverter().toJson(instance.id),
  'name': instance.name,
  'leaf': instance.leaf,
  'alias': instance.alias,
  'parentId': const CategoryIdConverter().toJson(instance.parentId),
  'otherMedia': instance.otherMedia,
  'position': instance.position,
  'empty': instance.empty,
  'media': instance.media,
  'files': instance.files,
  'kind': instance.kind,
  'learned': instance.learned,
};
