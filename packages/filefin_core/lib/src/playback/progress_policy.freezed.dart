// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'progress_policy.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SentReport {

 FileIndex get file; int get positionSeconds;
/// Create a copy of SentReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SentReportCopyWith<SentReport> get copyWith => _$SentReportCopyWithImpl<SentReport>(this as SentReport, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SentReport&&(identical(other.file, file) || other.file == file)&&(identical(other.positionSeconds, positionSeconds) || other.positionSeconds == positionSeconds));
}


@override
int get hashCode => Object.hash(runtimeType,file,positionSeconds);

@override
String toString() {
  return 'SentReport(file: $file, positionSeconds: $positionSeconds)';
}


}

/// @nodoc
abstract mixin class $SentReportCopyWith<$Res>  {
  factory $SentReportCopyWith(SentReport value, $Res Function(SentReport) _then) = _$SentReportCopyWithImpl;
@useResult
$Res call({
 FileIndex file, int positionSeconds
});




}
/// @nodoc
class _$SentReportCopyWithImpl<$Res>
    implements $SentReportCopyWith<$Res> {
  _$SentReportCopyWithImpl(this._self, this._then);

  final SentReport _self;
  final $Res Function(SentReport) _then;

/// Create a copy of SentReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? file = null,Object? positionSeconds = null,}) {
  return _then(_self.copyWith(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FileIndex,positionSeconds: null == positionSeconds ? _self.positionSeconds : positionSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SentReport].
extension SentReportPatterns on SentReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SentReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SentReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SentReport value)  $default,){
final _that = this;
switch (_that) {
case _SentReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SentReport value)?  $default,){
final _that = this;
switch (_that) {
case _SentReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FileIndex file,  int positionSeconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SentReport() when $default != null:
return $default(_that.file,_that.positionSeconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FileIndex file,  int positionSeconds)  $default,) {final _that = this;
switch (_that) {
case _SentReport():
return $default(_that.file,_that.positionSeconds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FileIndex file,  int positionSeconds)?  $default,) {final _that = this;
switch (_that) {
case _SentReport() when $default != null:
return $default(_that.file,_that.positionSeconds);case _:
  return null;

}
}

}

/// @nodoc


class _SentReport implements SentReport {
  const _SentReport({required this.file, required this.positionSeconds});
  

@override final  FileIndex file;
@override final  int positionSeconds;

/// Create a copy of SentReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SentReportCopyWith<_SentReport> get copyWith => __$SentReportCopyWithImpl<_SentReport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SentReport&&(identical(other.file, file) || other.file == file)&&(identical(other.positionSeconds, positionSeconds) || other.positionSeconds == positionSeconds));
}


@override
int get hashCode => Object.hash(runtimeType,file,positionSeconds);

@override
String toString() {
  return 'SentReport(file: $file, positionSeconds: $positionSeconds)';
}


}

/// @nodoc
abstract mixin class _$SentReportCopyWith<$Res> implements $SentReportCopyWith<$Res> {
  factory _$SentReportCopyWith(_SentReport value, $Res Function(_SentReport) _then) = __$SentReportCopyWithImpl;
@override @useResult
$Res call({
 FileIndex file, int positionSeconds
});




}
/// @nodoc
class __$SentReportCopyWithImpl<$Res>
    implements _$SentReportCopyWith<$Res> {
  __$SentReportCopyWithImpl(this._self, this._then);

  final _SentReport _self;
  final $Res Function(_SentReport) _then;

/// Create a copy of SentReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? file = null,Object? positionSeconds = null,}) {
  return _then(_SentReport(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FileIndex,positionSeconds: null == positionSeconds ? _self.positionSeconds : positionSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
