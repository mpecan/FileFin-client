// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AuthResult _$AuthResultFromJson(Map<String, dynamic> json) => _AuthResult(
  user: json['user'] as String? ?? '',
  admin: json['admin'] as bool? ?? false,
  alias: json['alias'] as String? ?? '',
  mdlUsername: json['mdlUsername'] as String? ?? '',
  malUsername: json['malUsername'] as String? ?? '',
);

Map<String, dynamic> _$AuthResultToJson(_AuthResult instance) =>
    <String, dynamic>{
      'user': instance.user,
      'admin': instance.admin,
      'alias': instance.alias,
      'mdlUsername': instance.mdlUsername,
      'malUsername': instance.malUsername,
    };
