// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MediaSummary {

@MediaIdConverter() MediaId get id; String get title; int get year; bool get hasPoster; bool get watched;
/// Create a copy of MediaSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaSummaryCopyWith<MediaSummary> get copyWith => _$MediaSummaryCopyWithImpl<MediaSummary>(this as MediaSummary, _$identity);

  /// Serializes this MediaSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.year, year) || other.year == year)&&(identical(other.hasPoster, hasPoster) || other.hasPoster == hasPoster)&&(identical(other.watched, watched) || other.watched == watched));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,year,hasPoster,watched);

@override
String toString() {
  return 'MediaSummary(id: $id, title: $title, year: $year, hasPoster: $hasPoster, watched: $watched)';
}


}

/// @nodoc
abstract mixin class $MediaSummaryCopyWith<$Res>  {
  factory $MediaSummaryCopyWith(MediaSummary value, $Res Function(MediaSummary) _then) = _$MediaSummaryCopyWithImpl;
@useResult
$Res call({
@MediaIdConverter() MediaId id, String title, int year, bool hasPoster, bool watched
});




}
/// @nodoc
class _$MediaSummaryCopyWithImpl<$Res>
    implements $MediaSummaryCopyWith<$Res> {
  _$MediaSummaryCopyWithImpl(this._self, this._then);

  final MediaSummary _self;
  final $Res Function(MediaSummary) _then;

/// Create a copy of MediaSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? year = null,Object? hasPoster = null,Object? watched = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as MediaId,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,year: null == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int,hasPoster: null == hasPoster ? _self.hasPoster : hasPoster // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [MediaSummary].
extension MediaSummaryPatterns on MediaSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MediaSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MediaSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MediaSummary value)  $default,){
final _that = this;
switch (_that) {
case _MediaSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MediaSummary value)?  $default,){
final _that = this;
switch (_that) {
case _MediaSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@MediaIdConverter()  MediaId id,  String title,  int year,  bool hasPoster,  bool watched)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MediaSummary() when $default != null:
return $default(_that.id,_that.title,_that.year,_that.hasPoster,_that.watched);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@MediaIdConverter()  MediaId id,  String title,  int year,  bool hasPoster,  bool watched)  $default,) {final _that = this;
switch (_that) {
case _MediaSummary():
return $default(_that.id,_that.title,_that.year,_that.hasPoster,_that.watched);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@MediaIdConverter()  MediaId id,  String title,  int year,  bool hasPoster,  bool watched)?  $default,) {final _that = this;
switch (_that) {
case _MediaSummary() when $default != null:
return $default(_that.id,_that.title,_that.year,_that.hasPoster,_that.watched);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MediaSummary implements MediaSummary {
  const _MediaSummary({@MediaIdConverter() this.id = const MediaId(''), this.title = '', this.year = 0, this.hasPoster = false, this.watched = false});
  factory _MediaSummary.fromJson(Map<String, dynamic> json) => _$MediaSummaryFromJson(json);

@override@JsonKey()@MediaIdConverter() final  MediaId id;
@override@JsonKey() final  String title;
@override@JsonKey() final  int year;
@override@JsonKey() final  bool hasPoster;
@override@JsonKey() final  bool watched;

/// Create a copy of MediaSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MediaSummaryCopyWith<_MediaSummary> get copyWith => __$MediaSummaryCopyWithImpl<_MediaSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MediaSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MediaSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.year, year) || other.year == year)&&(identical(other.hasPoster, hasPoster) || other.hasPoster == hasPoster)&&(identical(other.watched, watched) || other.watched == watched));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,year,hasPoster,watched);

@override
String toString() {
  return 'MediaSummary(id: $id, title: $title, year: $year, hasPoster: $hasPoster, watched: $watched)';
}


}

/// @nodoc
abstract mixin class _$MediaSummaryCopyWith<$Res> implements $MediaSummaryCopyWith<$Res> {
  factory _$MediaSummaryCopyWith(_MediaSummary value, $Res Function(_MediaSummary) _then) = __$MediaSummaryCopyWithImpl;
@override @useResult
$Res call({
@MediaIdConverter() MediaId id, String title, int year, bool hasPoster, bool watched
});




}
/// @nodoc
class __$MediaSummaryCopyWithImpl<$Res>
    implements _$MediaSummaryCopyWith<$Res> {
  __$MediaSummaryCopyWithImpl(this._self, this._then);

  final _MediaSummary _self;
  final $Res Function(_MediaSummary) _then;

/// Create a copy of MediaSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? year = null,Object? hasPoster = null,Object? watched = null,}) {
  return _then(_MediaSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as MediaId,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,year: null == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int,hasPoster: null == hasPoster ? _self.hasPoster : hasPoster // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
