// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'decision.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlaybackSettings {

 bool get wifiOnly; int get meteredWarnBytes;
/// Create a copy of PlaybackSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaybackSettingsCopyWith<PlaybackSettings> get copyWith => _$PlaybackSettingsCopyWithImpl<PlaybackSettings>(this as PlaybackSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaybackSettings&&(identical(other.wifiOnly, wifiOnly) || other.wifiOnly == wifiOnly)&&(identical(other.meteredWarnBytes, meteredWarnBytes) || other.meteredWarnBytes == meteredWarnBytes));
}


@override
int get hashCode => Object.hash(runtimeType,wifiOnly,meteredWarnBytes);

@override
String toString() {
  return 'PlaybackSettings(wifiOnly: $wifiOnly, meteredWarnBytes: $meteredWarnBytes)';
}


}

/// @nodoc
abstract mixin class $PlaybackSettingsCopyWith<$Res>  {
  factory $PlaybackSettingsCopyWith(PlaybackSettings value, $Res Function(PlaybackSettings) _then) = _$PlaybackSettingsCopyWithImpl;
@useResult
$Res call({
 bool wifiOnly, int meteredWarnBytes
});




}
/// @nodoc
class _$PlaybackSettingsCopyWithImpl<$Res>
    implements $PlaybackSettingsCopyWith<$Res> {
  _$PlaybackSettingsCopyWithImpl(this._self, this._then);

  final PlaybackSettings _self;
  final $Res Function(PlaybackSettings) _then;

/// Create a copy of PlaybackSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? wifiOnly = null,Object? meteredWarnBytes = null,}) {
  return _then(_self.copyWith(
wifiOnly: null == wifiOnly ? _self.wifiOnly : wifiOnly // ignore: cast_nullable_to_non_nullable
as bool,meteredWarnBytes: null == meteredWarnBytes ? _self.meteredWarnBytes : meteredWarnBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PlaybackSettings].
extension PlaybackSettingsPatterns on PlaybackSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlaybackSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlaybackSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlaybackSettings value)  $default,){
final _that = this;
switch (_that) {
case _PlaybackSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlaybackSettings value)?  $default,){
final _that = this;
switch (_that) {
case _PlaybackSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool wifiOnly,  int meteredWarnBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlaybackSettings() when $default != null:
return $default(_that.wifiOnly,_that.meteredWarnBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool wifiOnly,  int meteredWarnBytes)  $default,) {final _that = this;
switch (_that) {
case _PlaybackSettings():
return $default(_that.wifiOnly,_that.meteredWarnBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool wifiOnly,  int meteredWarnBytes)?  $default,) {final _that = this;
switch (_that) {
case _PlaybackSettings() when $default != null:
return $default(_that.wifiOnly,_that.meteredWarnBytes);case _:
  return null;

}
}

}

/// @nodoc


class _PlaybackSettings implements PlaybackSettings {
  const _PlaybackSettings({required this.wifiOnly, required this.meteredWarnBytes});
  

@override final  bool wifiOnly;
@override final  int meteredWarnBytes;

/// Create a copy of PlaybackSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlaybackSettingsCopyWith<_PlaybackSettings> get copyWith => __$PlaybackSettingsCopyWithImpl<_PlaybackSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlaybackSettings&&(identical(other.wifiOnly, wifiOnly) || other.wifiOnly == wifiOnly)&&(identical(other.meteredWarnBytes, meteredWarnBytes) || other.meteredWarnBytes == meteredWarnBytes));
}


@override
int get hashCode => Object.hash(runtimeType,wifiOnly,meteredWarnBytes);

@override
String toString() {
  return 'PlaybackSettings(wifiOnly: $wifiOnly, meteredWarnBytes: $meteredWarnBytes)';
}


}

/// @nodoc
abstract mixin class _$PlaybackSettingsCopyWith<$Res> implements $PlaybackSettingsCopyWith<$Res> {
  factory _$PlaybackSettingsCopyWith(_PlaybackSettings value, $Res Function(_PlaybackSettings) _then) = __$PlaybackSettingsCopyWithImpl;
@override @useResult
$Res call({
 bool wifiOnly, int meteredWarnBytes
});




}
/// @nodoc
class __$PlaybackSettingsCopyWithImpl<$Res>
    implements _$PlaybackSettingsCopyWith<$Res> {
  __$PlaybackSettingsCopyWithImpl(this._self, this._then);

  final _PlaybackSettings _self;
  final $Res Function(_PlaybackSettings) _then;

/// Create a copy of PlaybackSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? wifiOnly = null,Object? meteredWarnBytes = null,}) {
  return _then(_PlaybackSettings(
wifiOnly: null == wifiOnly ? _self.wifiOnly : wifiOnly // ignore: cast_nullable_to_non_nullable
as bool,meteredWarnBytes: null == meteredWarnBytes ? _self.meteredWarnBytes : meteredWarnBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
