// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ServerState _$ServerStateFromJson(Map<String, dynamic> json) => _ServerState(
  needsSetup: json['needsSetup'] as bool? ?? false,
  version: json['version'] as String? ?? '',
);

Map<String, dynamic> _$ServerStateToJson(_ServerState instance) =>
    <String, dynamic>{
      'needsSetup': instance.needsSetup,
      'version': instance.version,
    };
