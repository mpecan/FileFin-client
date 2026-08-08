// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'category.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Category {

@CategoryIdConverter() CategoryId get id; String get name; String get leaf; String get alias;@CategoryIdConverter() CategoryId get parentId; bool get otherMedia; int get position; bool get empty; int get media; int get files; String get kind; int get learned;
/// Create a copy of Category
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CategoryCopyWith<Category> get copyWith => _$CategoryCopyWithImpl<Category>(this as Category, _$identity);

  /// Serializes this Category to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Category&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.leaf, leaf) || other.leaf == leaf)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.otherMedia, otherMedia) || other.otherMedia == otherMedia)&&(identical(other.position, position) || other.position == position)&&(identical(other.empty, empty) || other.empty == empty)&&(identical(other.media, media) || other.media == media)&&(identical(other.files, files) || other.files == files)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.learned, learned) || other.learned == learned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,leaf,alias,parentId,otherMedia,position,empty,media,files,kind,learned);

@override
String toString() {
  return 'Category(id: $id, name: $name, leaf: $leaf, alias: $alias, parentId: $parentId, otherMedia: $otherMedia, position: $position, empty: $empty, media: $media, files: $files, kind: $kind, learned: $learned)';
}


}

/// @nodoc
abstract mixin class $CategoryCopyWith<$Res>  {
  factory $CategoryCopyWith(Category value, $Res Function(Category) _then) = _$CategoryCopyWithImpl;
@useResult
$Res call({
@CategoryIdConverter() CategoryId id, String name, String leaf, String alias,@CategoryIdConverter() CategoryId parentId, bool otherMedia, int position, bool empty, int media, int files, String kind, int learned
});




}
/// @nodoc
class _$CategoryCopyWithImpl<$Res>
    implements $CategoryCopyWith<$Res> {
  _$CategoryCopyWithImpl(this._self, this._then);

  final Category _self;
  final $Res Function(Category) _then;

/// Create a copy of Category
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? leaf = null,Object? alias = null,Object? parentId = null,Object? otherMedia = null,Object? position = null,Object? empty = null,Object? media = null,Object? files = null,Object? kind = null,Object? learned = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as CategoryId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,leaf: null == leaf ? _self.leaf : leaf // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,parentId: null == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as CategoryId,otherMedia: null == otherMedia ? _self.otherMedia : otherMedia // ignore: cast_nullable_to_non_nullable
as bool,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,empty: null == empty ? _self.empty : empty // ignore: cast_nullable_to_non_nullable
as bool,media: null == media ? _self.media : media // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,learned: null == learned ? _self.learned : learned // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Category].
extension CategoryPatterns on Category {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Category value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Category() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Category value)  $default,){
final _that = this;
switch (_that) {
case _Category():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Category value)?  $default,){
final _that = this;
switch (_that) {
case _Category() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@CategoryIdConverter()  CategoryId id,  String name,  String leaf,  String alias, @CategoryIdConverter()  CategoryId parentId,  bool otherMedia,  int position,  bool empty,  int media,  int files,  String kind,  int learned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Category() when $default != null:
return $default(_that.id,_that.name,_that.leaf,_that.alias,_that.parentId,_that.otherMedia,_that.position,_that.empty,_that.media,_that.files,_that.kind,_that.learned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@CategoryIdConverter()  CategoryId id,  String name,  String leaf,  String alias, @CategoryIdConverter()  CategoryId parentId,  bool otherMedia,  int position,  bool empty,  int media,  int files,  String kind,  int learned)  $default,) {final _that = this;
switch (_that) {
case _Category():
return $default(_that.id,_that.name,_that.leaf,_that.alias,_that.parentId,_that.otherMedia,_that.position,_that.empty,_that.media,_that.files,_that.kind,_that.learned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@CategoryIdConverter()  CategoryId id,  String name,  String leaf,  String alias, @CategoryIdConverter()  CategoryId parentId,  bool otherMedia,  int position,  bool empty,  int media,  int files,  String kind,  int learned)?  $default,) {final _that = this;
switch (_that) {
case _Category() when $default != null:
return $default(_that.id,_that.name,_that.leaf,_that.alias,_that.parentId,_that.otherMedia,_that.position,_that.empty,_that.media,_that.files,_that.kind,_that.learned);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Category implements Category {
  const _Category({@CategoryIdConverter() this.id = const CategoryId(0), this.name = '', this.leaf = '', this.alias = '', @CategoryIdConverter() this.parentId = const CategoryId(0), this.otherMedia = false, this.position = 0, this.empty = false, this.media = 0, this.files = 0, this.kind = '', this.learned = 0});
  factory _Category.fromJson(Map<String, dynamic> json) => _$CategoryFromJson(json);

@override@JsonKey()@CategoryIdConverter() final  CategoryId id;
@override@JsonKey() final  String name;
@override@JsonKey() final  String leaf;
@override@JsonKey() final  String alias;
@override@JsonKey()@CategoryIdConverter() final  CategoryId parentId;
@override@JsonKey() final  bool otherMedia;
@override@JsonKey() final  int position;
@override@JsonKey() final  bool empty;
@override@JsonKey() final  int media;
@override@JsonKey() final  int files;
@override@JsonKey() final  String kind;
@override@JsonKey() final  int learned;

/// Create a copy of Category
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CategoryCopyWith<_Category> get copyWith => __$CategoryCopyWithImpl<_Category>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CategoryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Category&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.leaf, leaf) || other.leaf == leaf)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.otherMedia, otherMedia) || other.otherMedia == otherMedia)&&(identical(other.position, position) || other.position == position)&&(identical(other.empty, empty) || other.empty == empty)&&(identical(other.media, media) || other.media == media)&&(identical(other.files, files) || other.files == files)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.learned, learned) || other.learned == learned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,leaf,alias,parentId,otherMedia,position,empty,media,files,kind,learned);

@override
String toString() {
  return 'Category(id: $id, name: $name, leaf: $leaf, alias: $alias, parentId: $parentId, otherMedia: $otherMedia, position: $position, empty: $empty, media: $media, files: $files, kind: $kind, learned: $learned)';
}


}

/// @nodoc
abstract mixin class _$CategoryCopyWith<$Res> implements $CategoryCopyWith<$Res> {
  factory _$CategoryCopyWith(_Category value, $Res Function(_Category) _then) = __$CategoryCopyWithImpl;
@override @useResult
$Res call({
@CategoryIdConverter() CategoryId id, String name, String leaf, String alias,@CategoryIdConverter() CategoryId parentId, bool otherMedia, int position, bool empty, int media, int files, String kind, int learned
});




}
/// @nodoc
class __$CategoryCopyWithImpl<$Res>
    implements _$CategoryCopyWith<$Res> {
  __$CategoryCopyWithImpl(this._self, this._then);

  final _Category _self;
  final $Res Function(_Category) _then;

/// Create a copy of Category
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? leaf = null,Object? alias = null,Object? parentId = null,Object? otherMedia = null,Object? position = null,Object? empty = null,Object? media = null,Object? files = null,Object? kind = null,Object? learned = null,}) {
  return _then(_Category(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as CategoryId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,leaf: null == leaf ? _self.leaf : leaf // ignore: cast_nullable_to_non_nullable
as String,alias: null == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String,parentId: null == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as CategoryId,otherMedia: null == otherMedia ? _self.otherMedia : otherMedia // ignore: cast_nullable_to_non_nullable
as bool,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as int,empty: null == empty ? _self.empty : empty // ignore: cast_nullable_to_non_nullable
as bool,media: null == media ? _self.media : media // ignore: cast_nullable_to_non_nullable
as int,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,learned: null == learned ? _self.learned : learned // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
