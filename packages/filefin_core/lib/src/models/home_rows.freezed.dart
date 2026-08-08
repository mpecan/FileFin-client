// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'home_rows.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$HomeRows {

@JsonKey(name: 'continue') List<MediaSummary> get continueRow; List<MediaSummary> get favorites; List<MediaSummary> get completed;
/// Create a copy of HomeRows
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HomeRowsCopyWith<HomeRows> get copyWith => _$HomeRowsCopyWithImpl<HomeRows>(this as HomeRows, _$identity);

  /// Serializes this HomeRows to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HomeRows&&const DeepCollectionEquality().equals(other.continueRow, continueRow)&&const DeepCollectionEquality().equals(other.favorites, favorites)&&const DeepCollectionEquality().equals(other.completed, completed));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(continueRow),const DeepCollectionEquality().hash(favorites),const DeepCollectionEquality().hash(completed));

@override
String toString() {
  return 'HomeRows(continueRow: $continueRow, favorites: $favorites, completed: $completed)';
}


}

/// @nodoc
abstract mixin class $HomeRowsCopyWith<$Res>  {
  factory $HomeRowsCopyWith(HomeRows value, $Res Function(HomeRows) _then) = _$HomeRowsCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'continue') List<MediaSummary> continueRow, List<MediaSummary> favorites, List<MediaSummary> completed
});




}
/// @nodoc
class _$HomeRowsCopyWithImpl<$Res>
    implements $HomeRowsCopyWith<$Res> {
  _$HomeRowsCopyWithImpl(this._self, this._then);

  final HomeRows _self;
  final $Res Function(HomeRows) _then;

/// Create a copy of HomeRows
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? continueRow = null,Object? favorites = null,Object? completed = null,}) {
  return _then(_self.copyWith(
continueRow: null == continueRow ? _self.continueRow : continueRow // ignore: cast_nullable_to_non_nullable
as List<MediaSummary>,favorites: null == favorites ? _self.favorites : favorites // ignore: cast_nullable_to_non_nullable
as List<MediaSummary>,completed: null == completed ? _self.completed : completed // ignore: cast_nullable_to_non_nullable
as List<MediaSummary>,
  ));
}

}


/// Adds pattern-matching-related methods to [HomeRows].
extension HomeRowsPatterns on HomeRows {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HomeRows value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HomeRows() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HomeRows value)  $default,){
final _that = this;
switch (_that) {
case _HomeRows():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HomeRows value)?  $default,){
final _that = this;
switch (_that) {
case _HomeRows() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'continue')  List<MediaSummary> continueRow,  List<MediaSummary> favorites,  List<MediaSummary> completed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HomeRows() when $default != null:
return $default(_that.continueRow,_that.favorites,_that.completed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'continue')  List<MediaSummary> continueRow,  List<MediaSummary> favorites,  List<MediaSummary> completed)  $default,) {final _that = this;
switch (_that) {
case _HomeRows():
return $default(_that.continueRow,_that.favorites,_that.completed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'continue')  List<MediaSummary> continueRow,  List<MediaSummary> favorites,  List<MediaSummary> completed)?  $default,) {final _that = this;
switch (_that) {
case _HomeRows() when $default != null:
return $default(_that.continueRow,_that.favorites,_that.completed);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HomeRows implements HomeRows {
  const _HomeRows({@JsonKey(name: 'continue') final  List<MediaSummary> continueRow = const <MediaSummary>[], final  List<MediaSummary> favorites = const <MediaSummary>[], final  List<MediaSummary> completed = const <MediaSummary>[]}): _continueRow = continueRow,_favorites = favorites,_completed = completed;
  factory _HomeRows.fromJson(Map<String, dynamic> json) => _$HomeRowsFromJson(json);

 final  List<MediaSummary> _continueRow;
@override@JsonKey(name: 'continue') List<MediaSummary> get continueRow {
  if (_continueRow is EqualUnmodifiableListView) return _continueRow;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_continueRow);
}

 final  List<MediaSummary> _favorites;
@override@JsonKey() List<MediaSummary> get favorites {
  if (_favorites is EqualUnmodifiableListView) return _favorites;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_favorites);
}

 final  List<MediaSummary> _completed;
@override@JsonKey() List<MediaSummary> get completed {
  if (_completed is EqualUnmodifiableListView) return _completed;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_completed);
}


/// Create a copy of HomeRows
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HomeRowsCopyWith<_HomeRows> get copyWith => __$HomeRowsCopyWithImpl<_HomeRows>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HomeRowsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HomeRows&&const DeepCollectionEquality().equals(other._continueRow, _continueRow)&&const DeepCollectionEquality().equals(other._favorites, _favorites)&&const DeepCollectionEquality().equals(other._completed, _completed));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_continueRow),const DeepCollectionEquality().hash(_favorites),const DeepCollectionEquality().hash(_completed));

@override
String toString() {
  return 'HomeRows(continueRow: $continueRow, favorites: $favorites, completed: $completed)';
}


}

/// @nodoc
abstract mixin class _$HomeRowsCopyWith<$Res> implements $HomeRowsCopyWith<$Res> {
  factory _$HomeRowsCopyWith(_HomeRows value, $Res Function(_HomeRows) _then) = __$HomeRowsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'continue') List<MediaSummary> continueRow, List<MediaSummary> favorites, List<MediaSummary> completed
});




}
/// @nodoc
class __$HomeRowsCopyWithImpl<$Res>
    implements _$HomeRowsCopyWith<$Res> {
  __$HomeRowsCopyWithImpl(this._self, this._then);

  final _HomeRows _self;
  final $Res Function(_HomeRows) _then;

/// Create a copy of HomeRows
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? continueRow = null,Object? favorites = null,Object? completed = null,}) {
  return _then(_HomeRows(
continueRow: null == continueRow ? _self._continueRow : continueRow // ignore: cast_nullable_to_non_nullable
as List<MediaSummary>,favorites: null == favorites ? _self._favorites : favorites // ignore: cast_nullable_to_non_nullable
as List<MediaSummary>,completed: null == completed ? _self._completed : completed // ignore: cast_nullable_to_non_nullable
as List<MediaSummary>,
  ));
}


}

// dart format on
