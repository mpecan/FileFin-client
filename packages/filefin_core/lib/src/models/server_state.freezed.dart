// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'server_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ServerState {

 bool get needsSetup; String get version;
/// Create a copy of ServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServerStateCopyWith<ServerState> get copyWith => _$ServerStateCopyWithImpl<ServerState>(this as ServerState, _$identity);

  /// Serializes this ServerState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ServerState&&(identical(other.needsSetup, needsSetup) || other.needsSetup == needsSetup)&&(identical(other.version, version) || other.version == version));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,needsSetup,version);

@override
String toString() {
  return 'ServerState(needsSetup: $needsSetup, version: $version)';
}


}

/// @nodoc
abstract mixin class $ServerStateCopyWith<$Res>  {
  factory $ServerStateCopyWith(ServerState value, $Res Function(ServerState) _then) = _$ServerStateCopyWithImpl;
@useResult
$Res call({
 bool needsSetup, String version
});




}
/// @nodoc
class _$ServerStateCopyWithImpl<$Res>
    implements $ServerStateCopyWith<$Res> {
  _$ServerStateCopyWithImpl(this._self, this._then);

  final ServerState _self;
  final $Res Function(ServerState) _then;

/// Create a copy of ServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? needsSetup = null,Object? version = null,}) {
  return _then(_self.copyWith(
needsSetup: null == needsSetup ? _self.needsSetup : needsSetup // ignore: cast_nullable_to_non_nullable
as bool,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ServerState].
extension ServerStatePatterns on ServerState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ServerState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ServerState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ServerState value)  $default,){
final _that = this;
switch (_that) {
case _ServerState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ServerState value)?  $default,){
final _that = this;
switch (_that) {
case _ServerState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool needsSetup,  String version)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ServerState() when $default != null:
return $default(_that.needsSetup,_that.version);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool needsSetup,  String version)  $default,) {final _that = this;
switch (_that) {
case _ServerState():
return $default(_that.needsSetup,_that.version);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool needsSetup,  String version)?  $default,) {final _that = this;
switch (_that) {
case _ServerState() when $default != null:
return $default(_that.needsSetup,_that.version);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ServerState implements ServerState {
  const _ServerState({this.needsSetup = false, this.version = ''});
  factory _ServerState.fromJson(Map<String, dynamic> json) => _$ServerStateFromJson(json);

@override@JsonKey() final  bool needsSetup;
@override@JsonKey() final  String version;

/// Create a copy of ServerState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ServerStateCopyWith<_ServerState> get copyWith => __$ServerStateCopyWithImpl<_ServerState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ServerStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ServerState&&(identical(other.needsSetup, needsSetup) || other.needsSetup == needsSetup)&&(identical(other.version, version) || other.version == version));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,needsSetup,version);

@override
String toString() {
  return 'ServerState(needsSetup: $needsSetup, version: $version)';
}


}

/// @nodoc
abstract mixin class _$ServerStateCopyWith<$Res> implements $ServerStateCopyWith<$Res> {
  factory _$ServerStateCopyWith(_ServerState value, $Res Function(_ServerState) _then) = __$ServerStateCopyWithImpl;
@override @useResult
$Res call({
 bool needsSetup, String version
});




}
/// @nodoc
class __$ServerStateCopyWithImpl<$Res>
    implements _$ServerStateCopyWith<$Res> {
  __$ServerStateCopyWithImpl(this._self, this._then);

  final _ServerState _self;
  final $Res Function(_ServerState) _then;

/// Create a copy of ServerState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? needsSetup = null,Object? version = null,}) {
  return _then(_ServerState(
needsSetup: null == needsSetup ? _self.needsSetup : needsSetup // ignore: cast_nullable_to_non_nullable
as bool,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
