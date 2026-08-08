// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'media_detail.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SubtitleInfo {

@SubtitleIndexConverter() SubtitleIndex get index; String get lang; String get label;
/// Create a copy of SubtitleInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubtitleInfoCopyWith<SubtitleInfo> get copyWith => _$SubtitleInfoCopyWithImpl<SubtitleInfo>(this as SubtitleInfo, _$identity);

  /// Serializes this SubtitleInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubtitleInfo&&(identical(other.index, index) || other.index == index)&&(identical(other.lang, lang) || other.lang == lang)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,index,lang,label);

@override
String toString() {
  return 'SubtitleInfo(index: $index, lang: $lang, label: $label)';
}


}

/// @nodoc
abstract mixin class $SubtitleInfoCopyWith<$Res>  {
  factory $SubtitleInfoCopyWith(SubtitleInfo value, $Res Function(SubtitleInfo) _then) = _$SubtitleInfoCopyWithImpl;
@useResult
$Res call({
@SubtitleIndexConverter() SubtitleIndex index, String lang, String label
});




}
/// @nodoc
class _$SubtitleInfoCopyWithImpl<$Res>
    implements $SubtitleInfoCopyWith<$Res> {
  _$SubtitleInfoCopyWithImpl(this._self, this._then);

  final SubtitleInfo _self;
  final $Res Function(SubtitleInfo) _then;

/// Create a copy of SubtitleInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? lang = null,Object? label = null,}) {
  return _then(_self.copyWith(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as SubtitleIndex,lang: null == lang ? _self.lang : lang // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SubtitleInfo].
extension SubtitleInfoPatterns on SubtitleInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubtitleInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubtitleInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubtitleInfo value)  $default,){
final _that = this;
switch (_that) {
case _SubtitleInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubtitleInfo value)?  $default,){
final _that = this;
switch (_that) {
case _SubtitleInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@SubtitleIndexConverter()  SubtitleIndex index,  String lang,  String label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubtitleInfo() when $default != null:
return $default(_that.index,_that.lang,_that.label);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@SubtitleIndexConverter()  SubtitleIndex index,  String lang,  String label)  $default,) {final _that = this;
switch (_that) {
case _SubtitleInfo():
return $default(_that.index,_that.lang,_that.label);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@SubtitleIndexConverter()  SubtitleIndex index,  String lang,  String label)?  $default,) {final _that = this;
switch (_that) {
case _SubtitleInfo() when $default != null:
return $default(_that.index,_that.lang,_that.label);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SubtitleInfo implements SubtitleInfo {
  const _SubtitleInfo({@SubtitleIndexConverter() this.index = const SubtitleIndex(0), this.lang = '', this.label = ''});
  factory _SubtitleInfo.fromJson(Map<String, dynamic> json) => _$SubtitleInfoFromJson(json);

@override@JsonKey()@SubtitleIndexConverter() final  SubtitleIndex index;
@override@JsonKey() final  String lang;
@override@JsonKey() final  String label;

/// Create a copy of SubtitleInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubtitleInfoCopyWith<_SubtitleInfo> get copyWith => __$SubtitleInfoCopyWithImpl<_SubtitleInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SubtitleInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubtitleInfo&&(identical(other.index, index) || other.index == index)&&(identical(other.lang, lang) || other.lang == lang)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,index,lang,label);

@override
String toString() {
  return 'SubtitleInfo(index: $index, lang: $lang, label: $label)';
}


}

/// @nodoc
abstract mixin class _$SubtitleInfoCopyWith<$Res> implements $SubtitleInfoCopyWith<$Res> {
  factory _$SubtitleInfoCopyWith(_SubtitleInfo value, $Res Function(_SubtitleInfo) _then) = __$SubtitleInfoCopyWithImpl;
@override @useResult
$Res call({
@SubtitleIndexConverter() SubtitleIndex index, String lang, String label
});




}
/// @nodoc
class __$SubtitleInfoCopyWithImpl<$Res>
    implements _$SubtitleInfoCopyWith<$Res> {
  __$SubtitleInfoCopyWithImpl(this._self, this._then);

  final _SubtitleInfo _self;
  final $Res Function(_SubtitleInfo) _then;

/// Create a copy of SubtitleInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? lang = null,Object? label = null,}) {
  return _then(_SubtitleInfo(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as SubtitleIndex,lang: null == lang ? _self.lang : lang // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$FileInfo {

@FileIndexConverter() FileIndex get index; String get name; String get path; int get size; int get season; int get episode; String get ext; bool get transcode; bool get watched; List<SubtitleInfo> get subtitles;
/// Create a copy of FileInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileInfoCopyWith<FileInfo> get copyWith => _$FileInfoCopyWithImpl<FileInfo>(this as FileInfo, _$identity);

  /// Serializes this FileInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileInfo&&(identical(other.index, index) || other.index == index)&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.size, size) || other.size == size)&&(identical(other.season, season) || other.season == season)&&(identical(other.episode, episode) || other.episode == episode)&&(identical(other.ext, ext) || other.ext == ext)&&(identical(other.transcode, transcode) || other.transcode == transcode)&&(identical(other.watched, watched) || other.watched == watched)&&const DeepCollectionEquality().equals(other.subtitles, subtitles));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,index,name,path,size,season,episode,ext,transcode,watched,const DeepCollectionEquality().hash(subtitles));

@override
String toString() {
  return 'FileInfo(index: $index, name: $name, path: $path, size: $size, season: $season, episode: $episode, ext: $ext, transcode: $transcode, watched: $watched, subtitles: $subtitles)';
}


}

/// @nodoc
abstract mixin class $FileInfoCopyWith<$Res>  {
  factory $FileInfoCopyWith(FileInfo value, $Res Function(FileInfo) _then) = _$FileInfoCopyWithImpl;
@useResult
$Res call({
@FileIndexConverter() FileIndex index, String name, String path, int size, int season, int episode, String ext, bool transcode, bool watched, List<SubtitleInfo> subtitles
});




}
/// @nodoc
class _$FileInfoCopyWithImpl<$Res>
    implements $FileInfoCopyWith<$Res> {
  _$FileInfoCopyWithImpl(this._self, this._then);

  final FileInfo _self;
  final $Res Function(FileInfo) _then;

/// Create a copy of FileInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? name = null,Object? path = null,Object? size = null,Object? season = null,Object? episode = null,Object? ext = null,Object? transcode = null,Object? watched = null,Object? subtitles = null,}) {
  return _then(_self.copyWith(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as FileIndex,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,episode: null == episode ? _self.episode : episode // ignore: cast_nullable_to_non_nullable
as int,ext: null == ext ? _self.ext : ext // ignore: cast_nullable_to_non_nullable
as String,transcode: null == transcode ? _self.transcode : transcode // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,subtitles: null == subtitles ? _self.subtitles : subtitles // ignore: cast_nullable_to_non_nullable
as List<SubtitleInfo>,
  ));
}

}


/// Adds pattern-matching-related methods to [FileInfo].
extension FileInfoPatterns on FileInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileInfo value)  $default,){
final _that = this;
switch (_that) {
case _FileInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileInfo value)?  $default,){
final _that = this;
switch (_that) {
case _FileInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@FileIndexConverter()  FileIndex index,  String name,  String path,  int size,  int season,  int episode,  String ext,  bool transcode,  bool watched,  List<SubtitleInfo> subtitles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileInfo() when $default != null:
return $default(_that.index,_that.name,_that.path,_that.size,_that.season,_that.episode,_that.ext,_that.transcode,_that.watched,_that.subtitles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@FileIndexConverter()  FileIndex index,  String name,  String path,  int size,  int season,  int episode,  String ext,  bool transcode,  bool watched,  List<SubtitleInfo> subtitles)  $default,) {final _that = this;
switch (_that) {
case _FileInfo():
return $default(_that.index,_that.name,_that.path,_that.size,_that.season,_that.episode,_that.ext,_that.transcode,_that.watched,_that.subtitles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@FileIndexConverter()  FileIndex index,  String name,  String path,  int size,  int season,  int episode,  String ext,  bool transcode,  bool watched,  List<SubtitleInfo> subtitles)?  $default,) {final _that = this;
switch (_that) {
case _FileInfo() when $default != null:
return $default(_that.index,_that.name,_that.path,_that.size,_that.season,_that.episode,_that.ext,_that.transcode,_that.watched,_that.subtitles);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FileInfo implements FileInfo {
  const _FileInfo({@FileIndexConverter() this.index = const FileIndex(0), this.name = '', this.path = '', this.size = 0, this.season = 0, this.episode = 0, this.ext = '', this.transcode = false, this.watched = false, final  List<SubtitleInfo> subtitles = const <SubtitleInfo>[]}): _subtitles = subtitles;
  factory _FileInfo.fromJson(Map<String, dynamic> json) => _$FileInfoFromJson(json);

@override@JsonKey()@FileIndexConverter() final  FileIndex index;
@override@JsonKey() final  String name;
@override@JsonKey() final  String path;
@override@JsonKey() final  int size;
@override@JsonKey() final  int season;
@override@JsonKey() final  int episode;
@override@JsonKey() final  String ext;
@override@JsonKey() final  bool transcode;
@override@JsonKey() final  bool watched;
 final  List<SubtitleInfo> _subtitles;
@override@JsonKey() List<SubtitleInfo> get subtitles {
  if (_subtitles is EqualUnmodifiableListView) return _subtitles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_subtitles);
}


/// Create a copy of FileInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileInfoCopyWith<_FileInfo> get copyWith => __$FileInfoCopyWithImpl<_FileInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FileInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileInfo&&(identical(other.index, index) || other.index == index)&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.size, size) || other.size == size)&&(identical(other.season, season) || other.season == season)&&(identical(other.episode, episode) || other.episode == episode)&&(identical(other.ext, ext) || other.ext == ext)&&(identical(other.transcode, transcode) || other.transcode == transcode)&&(identical(other.watched, watched) || other.watched == watched)&&const DeepCollectionEquality().equals(other._subtitles, _subtitles));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,index,name,path,size,season,episode,ext,transcode,watched,const DeepCollectionEquality().hash(_subtitles));

@override
String toString() {
  return 'FileInfo(index: $index, name: $name, path: $path, size: $size, season: $season, episode: $episode, ext: $ext, transcode: $transcode, watched: $watched, subtitles: $subtitles)';
}


}

/// @nodoc
abstract mixin class _$FileInfoCopyWith<$Res> implements $FileInfoCopyWith<$Res> {
  factory _$FileInfoCopyWith(_FileInfo value, $Res Function(_FileInfo) _then) = __$FileInfoCopyWithImpl;
@override @useResult
$Res call({
@FileIndexConverter() FileIndex index, String name, String path, int size, int season, int episode, String ext, bool transcode, bool watched, List<SubtitleInfo> subtitles
});




}
/// @nodoc
class __$FileInfoCopyWithImpl<$Res>
    implements _$FileInfoCopyWith<$Res> {
  __$FileInfoCopyWithImpl(this._self, this._then);

  final _FileInfo _self;
  final $Res Function(_FileInfo) _then;

/// Create a copy of FileInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? name = null,Object? path = null,Object? size = null,Object? season = null,Object? episode = null,Object? ext = null,Object? transcode = null,Object? watched = null,Object? subtitles = null,}) {
  return _then(_FileInfo(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as FileIndex,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,episode: null == episode ? _self.episode : episode // ignore: cast_nullable_to_non_nullable
as int,ext: null == ext ? _self.ext : ext // ignore: cast_nullable_to_non_nullable
as String,transcode: null == transcode ? _self.transcode : transcode // ignore: cast_nullable_to_non_nullable
as bool,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,subtitles: null == subtitles ? _self._subtitles : subtitles // ignore: cast_nullable_to_non_nullable
as List<SubtitleInfo>,
  ));
}


}


/// @nodoc
mixin _$MetaPair {

 String get key; String get value;
/// Create a copy of MetaPair
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetaPairCopyWith<MetaPair> get copyWith => _$MetaPairCopyWithImpl<MetaPair>(this as MetaPair, _$identity);

  /// Serializes this MetaPair to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetaPair&&(identical(other.key, key) || other.key == key)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,key,value);

@override
String toString() {
  return 'MetaPair(key: $key, value: $value)';
}


}

/// @nodoc
abstract mixin class $MetaPairCopyWith<$Res>  {
  factory $MetaPairCopyWith(MetaPair value, $Res Function(MetaPair) _then) = _$MetaPairCopyWithImpl;
@useResult
$Res call({
 String key, String value
});




}
/// @nodoc
class _$MetaPairCopyWithImpl<$Res>
    implements $MetaPairCopyWith<$Res> {
  _$MetaPairCopyWithImpl(this._self, this._then);

  final MetaPair _self;
  final $Res Function(MetaPair) _then;

/// Create a copy of MetaPair
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? value = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [MetaPair].
extension MetaPairPatterns on MetaPair {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetaPair value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetaPair() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetaPair value)  $default,){
final _that = this;
switch (_that) {
case _MetaPair():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetaPair value)?  $default,){
final _that = this;
switch (_that) {
case _MetaPair() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetaPair() when $default != null:
return $default(_that.key,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String value)  $default,) {final _that = this;
switch (_that) {
case _MetaPair():
return $default(_that.key,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String value)?  $default,) {final _that = this;
switch (_that) {
case _MetaPair() when $default != null:
return $default(_that.key,_that.value);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MetaPair implements MetaPair {
  const _MetaPair({this.key = '', this.value = ''});
  factory _MetaPair.fromJson(Map<String, dynamic> json) => _$MetaPairFromJson(json);

@override@JsonKey() final  String key;
@override@JsonKey() final  String value;

/// Create a copy of MetaPair
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetaPairCopyWith<_MetaPair> get copyWith => __$MetaPairCopyWithImpl<_MetaPair>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MetaPairToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetaPair&&(identical(other.key, key) || other.key == key)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,key,value);

@override
String toString() {
  return 'MetaPair(key: $key, value: $value)';
}


}

/// @nodoc
abstract mixin class _$MetaPairCopyWith<$Res> implements $MetaPairCopyWith<$Res> {
  factory _$MetaPairCopyWith(_MetaPair value, $Res Function(_MetaPair) _then) = __$MetaPairCopyWithImpl;
@override @useResult
$Res call({
 String key, String value
});




}
/// @nodoc
class __$MetaPairCopyWithImpl<$Res>
    implements _$MetaPairCopyWith<$Res> {
  __$MetaPairCopyWithImpl(this._self, this._then);

  final _MetaPair _self;
  final $Res Function(_MetaPair) _then;

/// Create a copy of MetaPair
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? value = null,}) {
  return _then(_MetaPair(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$MediaDetail {

@MediaIdConverter() MediaId get id; String get title; int get year; String get description; String get plot; bool get hasPoster; List<FileInfo> get files; List<MetaPair> get metadata; List<MetaPair> get ratings; List<MetaPair> get technical; List<String> get actors; List<String> get genres; List<String> get tags; bool get watched; bool get favorite; int get rating; int get continueIndex; int get continueSeconds;
/// Create a copy of MediaDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MediaDetailCopyWith<MediaDetail> get copyWith => _$MediaDetailCopyWithImpl<MediaDetail>(this as MediaDetail, _$identity);

  /// Serializes this MediaDetail to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MediaDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.year, year) || other.year == year)&&(identical(other.description, description) || other.description == description)&&(identical(other.plot, plot) || other.plot == plot)&&(identical(other.hasPoster, hasPoster) || other.hasPoster == hasPoster)&&const DeepCollectionEquality().equals(other.files, files)&&const DeepCollectionEquality().equals(other.metadata, metadata)&&const DeepCollectionEquality().equals(other.ratings, ratings)&&const DeepCollectionEquality().equals(other.technical, technical)&&const DeepCollectionEquality().equals(other.actors, actors)&&const DeepCollectionEquality().equals(other.genres, genres)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.favorite, favorite) || other.favorite == favorite)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.continueIndex, continueIndex) || other.continueIndex == continueIndex)&&(identical(other.continueSeconds, continueSeconds) || other.continueSeconds == continueSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,year,description,plot,hasPoster,const DeepCollectionEquality().hash(files),const DeepCollectionEquality().hash(metadata),const DeepCollectionEquality().hash(ratings),const DeepCollectionEquality().hash(technical),const DeepCollectionEquality().hash(actors),const DeepCollectionEquality().hash(genres),const DeepCollectionEquality().hash(tags),watched,favorite,rating,continueIndex,continueSeconds);

@override
String toString() {
  return 'MediaDetail(id: $id, title: $title, year: $year, description: $description, plot: $plot, hasPoster: $hasPoster, files: $files, metadata: $metadata, ratings: $ratings, technical: $technical, actors: $actors, genres: $genres, tags: $tags, watched: $watched, favorite: $favorite, rating: $rating, continueIndex: $continueIndex, continueSeconds: $continueSeconds)';
}


}

/// @nodoc
abstract mixin class $MediaDetailCopyWith<$Res>  {
  factory $MediaDetailCopyWith(MediaDetail value, $Res Function(MediaDetail) _then) = _$MediaDetailCopyWithImpl;
@useResult
$Res call({
@MediaIdConverter() MediaId id, String title, int year, String description, String plot, bool hasPoster, List<FileInfo> files, List<MetaPair> metadata, List<MetaPair> ratings, List<MetaPair> technical, List<String> actors, List<String> genres, List<String> tags, bool watched, bool favorite, int rating, int continueIndex, int continueSeconds
});




}
/// @nodoc
class _$MediaDetailCopyWithImpl<$Res>
    implements $MediaDetailCopyWith<$Res> {
  _$MediaDetailCopyWithImpl(this._self, this._then);

  final MediaDetail _self;
  final $Res Function(MediaDetail) _then;

/// Create a copy of MediaDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? year = null,Object? description = null,Object? plot = null,Object? hasPoster = null,Object? files = null,Object? metadata = null,Object? ratings = null,Object? technical = null,Object? actors = null,Object? genres = null,Object? tags = null,Object? watched = null,Object? favorite = null,Object? rating = null,Object? continueIndex = null,Object? continueSeconds = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as MediaId,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,year: null == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,plot: null == plot ? _self.plot : plot // ignore: cast_nullable_to_non_nullable
as String,hasPoster: null == hasPoster ? _self.hasPoster : hasPoster // ignore: cast_nullable_to_non_nullable
as bool,files: null == files ? _self.files : files // ignore: cast_nullable_to_non_nullable
as List<FileInfo>,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as List<MetaPair>,ratings: null == ratings ? _self.ratings : ratings // ignore: cast_nullable_to_non_nullable
as List<MetaPair>,technical: null == technical ? _self.technical : technical // ignore: cast_nullable_to_non_nullable
as List<MetaPair>,actors: null == actors ? _self.actors : actors // ignore: cast_nullable_to_non_nullable
as List<String>,genres: null == genres ? _self.genres : genres // ignore: cast_nullable_to_non_nullable
as List<String>,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,favorite: null == favorite ? _self.favorite : favorite // ignore: cast_nullable_to_non_nullable
as bool,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int,continueIndex: null == continueIndex ? _self.continueIndex : continueIndex // ignore: cast_nullable_to_non_nullable
as int,continueSeconds: null == continueSeconds ? _self.continueSeconds : continueSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [MediaDetail].
extension MediaDetailPatterns on MediaDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MediaDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MediaDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MediaDetail value)  $default,){
final _that = this;
switch (_that) {
case _MediaDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MediaDetail value)?  $default,){
final _that = this;
switch (_that) {
case _MediaDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@MediaIdConverter()  MediaId id,  String title,  int year,  String description,  String plot,  bool hasPoster,  List<FileInfo> files,  List<MetaPair> metadata,  List<MetaPair> ratings,  List<MetaPair> technical,  List<String> actors,  List<String> genres,  List<String> tags,  bool watched,  bool favorite,  int rating,  int continueIndex,  int continueSeconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MediaDetail() when $default != null:
return $default(_that.id,_that.title,_that.year,_that.description,_that.plot,_that.hasPoster,_that.files,_that.metadata,_that.ratings,_that.technical,_that.actors,_that.genres,_that.tags,_that.watched,_that.favorite,_that.rating,_that.continueIndex,_that.continueSeconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@MediaIdConverter()  MediaId id,  String title,  int year,  String description,  String plot,  bool hasPoster,  List<FileInfo> files,  List<MetaPair> metadata,  List<MetaPair> ratings,  List<MetaPair> technical,  List<String> actors,  List<String> genres,  List<String> tags,  bool watched,  bool favorite,  int rating,  int continueIndex,  int continueSeconds)  $default,) {final _that = this;
switch (_that) {
case _MediaDetail():
return $default(_that.id,_that.title,_that.year,_that.description,_that.plot,_that.hasPoster,_that.files,_that.metadata,_that.ratings,_that.technical,_that.actors,_that.genres,_that.tags,_that.watched,_that.favorite,_that.rating,_that.continueIndex,_that.continueSeconds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@MediaIdConverter()  MediaId id,  String title,  int year,  String description,  String plot,  bool hasPoster,  List<FileInfo> files,  List<MetaPair> metadata,  List<MetaPair> ratings,  List<MetaPair> technical,  List<String> actors,  List<String> genres,  List<String> tags,  bool watched,  bool favorite,  int rating,  int continueIndex,  int continueSeconds)?  $default,) {final _that = this;
switch (_that) {
case _MediaDetail() when $default != null:
return $default(_that.id,_that.title,_that.year,_that.description,_that.plot,_that.hasPoster,_that.files,_that.metadata,_that.ratings,_that.technical,_that.actors,_that.genres,_that.tags,_that.watched,_that.favorite,_that.rating,_that.continueIndex,_that.continueSeconds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MediaDetail implements MediaDetail {
  const _MediaDetail({@MediaIdConverter() this.id = const MediaId(''), this.title = '', this.year = 0, this.description = '', this.plot = '', this.hasPoster = false, final  List<FileInfo> files = const <FileInfo>[], final  List<MetaPair> metadata = const <MetaPair>[], final  List<MetaPair> ratings = const <MetaPair>[], final  List<MetaPair> technical = const <MetaPair>[], final  List<String> actors = const <String>[], final  List<String> genres = const <String>[], final  List<String> tags = const <String>[], this.watched = false, this.favorite = false, this.rating = 0, this.continueIndex = 0, this.continueSeconds = 0}): _files = files,_metadata = metadata,_ratings = ratings,_technical = technical,_actors = actors,_genres = genres,_tags = tags;
  factory _MediaDetail.fromJson(Map<String, dynamic> json) => _$MediaDetailFromJson(json);

@override@JsonKey()@MediaIdConverter() final  MediaId id;
@override@JsonKey() final  String title;
@override@JsonKey() final  int year;
@override@JsonKey() final  String description;
@override@JsonKey() final  String plot;
@override@JsonKey() final  bool hasPoster;
 final  List<FileInfo> _files;
@override@JsonKey() List<FileInfo> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

 final  List<MetaPair> _metadata;
@override@JsonKey() List<MetaPair> get metadata {
  if (_metadata is EqualUnmodifiableListView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_metadata);
}

 final  List<MetaPair> _ratings;
@override@JsonKey() List<MetaPair> get ratings {
  if (_ratings is EqualUnmodifiableListView) return _ratings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ratings);
}

 final  List<MetaPair> _technical;
@override@JsonKey() List<MetaPair> get technical {
  if (_technical is EqualUnmodifiableListView) return _technical;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_technical);
}

 final  List<String> _actors;
@override@JsonKey() List<String> get actors {
  if (_actors is EqualUnmodifiableListView) return _actors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_actors);
}

 final  List<String> _genres;
@override@JsonKey() List<String> get genres {
  if (_genres is EqualUnmodifiableListView) return _genres;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_genres);
}

 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey() final  bool watched;
@override@JsonKey() final  bool favorite;
@override@JsonKey() final  int rating;
@override@JsonKey() final  int continueIndex;
@override@JsonKey() final  int continueSeconds;

/// Create a copy of MediaDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MediaDetailCopyWith<_MediaDetail> get copyWith => __$MediaDetailCopyWithImpl<_MediaDetail>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MediaDetailToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MediaDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.year, year) || other.year == year)&&(identical(other.description, description) || other.description == description)&&(identical(other.plot, plot) || other.plot == plot)&&(identical(other.hasPoster, hasPoster) || other.hasPoster == hasPoster)&&const DeepCollectionEquality().equals(other._files, _files)&&const DeepCollectionEquality().equals(other._metadata, _metadata)&&const DeepCollectionEquality().equals(other._ratings, _ratings)&&const DeepCollectionEquality().equals(other._technical, _technical)&&const DeepCollectionEquality().equals(other._actors, _actors)&&const DeepCollectionEquality().equals(other._genres, _genres)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.favorite, favorite) || other.favorite == favorite)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.continueIndex, continueIndex) || other.continueIndex == continueIndex)&&(identical(other.continueSeconds, continueSeconds) || other.continueSeconds == continueSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,year,description,plot,hasPoster,const DeepCollectionEquality().hash(_files),const DeepCollectionEquality().hash(_metadata),const DeepCollectionEquality().hash(_ratings),const DeepCollectionEquality().hash(_technical),const DeepCollectionEquality().hash(_actors),const DeepCollectionEquality().hash(_genres),const DeepCollectionEquality().hash(_tags),watched,favorite,rating,continueIndex,continueSeconds);

@override
String toString() {
  return 'MediaDetail(id: $id, title: $title, year: $year, description: $description, plot: $plot, hasPoster: $hasPoster, files: $files, metadata: $metadata, ratings: $ratings, technical: $technical, actors: $actors, genres: $genres, tags: $tags, watched: $watched, favorite: $favorite, rating: $rating, continueIndex: $continueIndex, continueSeconds: $continueSeconds)';
}


}

/// @nodoc
abstract mixin class _$MediaDetailCopyWith<$Res> implements $MediaDetailCopyWith<$Res> {
  factory _$MediaDetailCopyWith(_MediaDetail value, $Res Function(_MediaDetail) _then) = __$MediaDetailCopyWithImpl;
@override @useResult
$Res call({
@MediaIdConverter() MediaId id, String title, int year, String description, String plot, bool hasPoster, List<FileInfo> files, List<MetaPair> metadata, List<MetaPair> ratings, List<MetaPair> technical, List<String> actors, List<String> genres, List<String> tags, bool watched, bool favorite, int rating, int continueIndex, int continueSeconds
});




}
/// @nodoc
class __$MediaDetailCopyWithImpl<$Res>
    implements _$MediaDetailCopyWith<$Res> {
  __$MediaDetailCopyWithImpl(this._self, this._then);

  final _MediaDetail _self;
  final $Res Function(_MediaDetail) _then;

/// Create a copy of MediaDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? year = null,Object? description = null,Object? plot = null,Object? hasPoster = null,Object? files = null,Object? metadata = null,Object? ratings = null,Object? technical = null,Object? actors = null,Object? genres = null,Object? tags = null,Object? watched = null,Object? favorite = null,Object? rating = null,Object? continueIndex = null,Object? continueSeconds = null,}) {
  return _then(_MediaDetail(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as MediaId,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,year: null == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,plot: null == plot ? _self.plot : plot // ignore: cast_nullable_to_non_nullable
as String,hasPoster: null == hasPoster ? _self.hasPoster : hasPoster // ignore: cast_nullable_to_non_nullable
as bool,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<FileInfo>,metadata: null == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as List<MetaPair>,ratings: null == ratings ? _self._ratings : ratings // ignore: cast_nullable_to_non_nullable
as List<MetaPair>,technical: null == technical ? _self._technical : technical // ignore: cast_nullable_to_non_nullable
as List<MetaPair>,actors: null == actors ? _self._actors : actors // ignore: cast_nullable_to_non_nullable
as List<String>,genres: null == genres ? _self._genres : genres // ignore: cast_nullable_to_non_nullable
as List<String>,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,favorite: null == favorite ? _self.favorite : favorite // ignore: cast_nullable_to_non_nullable
as bool,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int,continueIndex: null == continueIndex ? _self.continueIndex : continueIndex // ignore: cast_nullable_to_non_nullable
as int,continueSeconds: null == continueSeconds ? _self.continueSeconds : continueSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
