// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'watch_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ResumePointer {

 FileIndex get file; int get seconds;
/// Create a copy of ResumePointer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResumePointerCopyWith<ResumePointer> get copyWith => _$ResumePointerCopyWithImpl<ResumePointer>(this as ResumePointer, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResumePointer&&(identical(other.file, file) || other.file == file)&&(identical(other.seconds, seconds) || other.seconds == seconds));
}


@override
int get hashCode => Object.hash(runtimeType,file,seconds);

@override
String toString() {
  return 'ResumePointer(file: $file, seconds: $seconds)';
}


}

/// @nodoc
abstract mixin class $ResumePointerCopyWith<$Res>  {
  factory $ResumePointerCopyWith(ResumePointer value, $Res Function(ResumePointer) _then) = _$ResumePointerCopyWithImpl;
@useResult
$Res call({
 FileIndex file, int seconds
});




}
/// @nodoc
class _$ResumePointerCopyWithImpl<$Res>
    implements $ResumePointerCopyWith<$Res> {
  _$ResumePointerCopyWithImpl(this._self, this._then);

  final ResumePointer _self;
  final $Res Function(ResumePointer) _then;

/// Create a copy of ResumePointer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? file = null,Object? seconds = null,}) {
  return _then(_self.copyWith(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FileIndex,seconds: null == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ResumePointer].
extension ResumePointerPatterns on ResumePointer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ResumePointer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ResumePointer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ResumePointer value)  $default,){
final _that = this;
switch (_that) {
case _ResumePointer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ResumePointer value)?  $default,){
final _that = this;
switch (_that) {
case _ResumePointer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FileIndex file,  int seconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ResumePointer() when $default != null:
return $default(_that.file,_that.seconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FileIndex file,  int seconds)  $default,) {final _that = this;
switch (_that) {
case _ResumePointer():
return $default(_that.file,_that.seconds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FileIndex file,  int seconds)?  $default,) {final _that = this;
switch (_that) {
case _ResumePointer() when $default != null:
return $default(_that.file,_that.seconds);case _:
  return null;

}
}

}

/// @nodoc


class _ResumePointer implements ResumePointer {
  const _ResumePointer({required this.file, required this.seconds});
  

@override final  FileIndex file;
@override final  int seconds;

/// Create a copy of ResumePointer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResumePointerCopyWith<_ResumePointer> get copyWith => __$ResumePointerCopyWithImpl<_ResumePointer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ResumePointer&&(identical(other.file, file) || other.file == file)&&(identical(other.seconds, seconds) || other.seconds == seconds));
}


@override
int get hashCode => Object.hash(runtimeType,file,seconds);

@override
String toString() {
  return 'ResumePointer(file: $file, seconds: $seconds)';
}


}

/// @nodoc
abstract mixin class _$ResumePointerCopyWith<$Res> implements $ResumePointerCopyWith<$Res> {
  factory _$ResumePointerCopyWith(_ResumePointer value, $Res Function(_ResumePointer) _then) = __$ResumePointerCopyWithImpl;
@override @useResult
$Res call({
 FileIndex file, int seconds
});




}
/// @nodoc
class __$ResumePointerCopyWithImpl<$Res>
    implements _$ResumePointerCopyWith<$Res> {
  __$ResumePointerCopyWithImpl(this._self, this._then);

  final _ResumePointer _self;
  final $Res Function(_ResumePointer) _then;

/// Create a copy of ResumePointer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? file = null,Object? seconds = null,}) {
  return _then(_ResumePointer(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FileIndex,seconds: null == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WatchState {

 ResumePointer? get pointer; bool get watched; bool get favorite; int get rating;
/// Create a copy of WatchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WatchStateCopyWith<WatchState> get copyWith => _$WatchStateCopyWithImpl<WatchState>(this as WatchState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WatchState&&(identical(other.pointer, pointer) || other.pointer == pointer)&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.favorite, favorite) || other.favorite == favorite)&&(identical(other.rating, rating) || other.rating == rating));
}


@override
int get hashCode => Object.hash(runtimeType,pointer,watched,favorite,rating);

@override
String toString() {
  return 'WatchState(pointer: $pointer, watched: $watched, favorite: $favorite, rating: $rating)';
}


}

/// @nodoc
abstract mixin class $WatchStateCopyWith<$Res>  {
  factory $WatchStateCopyWith(WatchState value, $Res Function(WatchState) _then) = _$WatchStateCopyWithImpl;
@useResult
$Res call({
 ResumePointer? pointer, bool watched, bool favorite, int rating
});


$ResumePointerCopyWith<$Res>? get pointer;

}
/// @nodoc
class _$WatchStateCopyWithImpl<$Res>
    implements $WatchStateCopyWith<$Res> {
  _$WatchStateCopyWithImpl(this._self, this._then);

  final WatchState _self;
  final $Res Function(WatchState) _then;

/// Create a copy of WatchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pointer = freezed,Object? watched = null,Object? favorite = null,Object? rating = null,}) {
  return _then(_self.copyWith(
pointer: freezed == pointer ? _self.pointer : pointer // ignore: cast_nullable_to_non_nullable
as ResumePointer?,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,favorite: null == favorite ? _self.favorite : favorite // ignore: cast_nullable_to_non_nullable
as bool,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of WatchState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResumePointerCopyWith<$Res>? get pointer {
    if (_self.pointer == null) {
    return null;
  }

  return $ResumePointerCopyWith<$Res>(_self.pointer!, (value) {
    return _then(_self.copyWith(pointer: value));
  });
}
}


/// Adds pattern-matching-related methods to [WatchState].
extension WatchStatePatterns on WatchState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WatchState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WatchState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WatchState value)  $default,){
final _that = this;
switch (_that) {
case _WatchState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WatchState value)?  $default,){
final _that = this;
switch (_that) {
case _WatchState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ResumePointer? pointer,  bool watched,  bool favorite,  int rating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WatchState() when $default != null:
return $default(_that.pointer,_that.watched,_that.favorite,_that.rating);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ResumePointer? pointer,  bool watched,  bool favorite,  int rating)  $default,) {final _that = this;
switch (_that) {
case _WatchState():
return $default(_that.pointer,_that.watched,_that.favorite,_that.rating);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ResumePointer? pointer,  bool watched,  bool favorite,  int rating)?  $default,) {final _that = this;
switch (_that) {
case _WatchState() when $default != null:
return $default(_that.pointer,_that.watched,_that.favorite,_that.rating);case _:
  return null;

}
}

}

/// @nodoc


class _WatchState extends WatchState {
  const _WatchState({this.pointer, this.watched = false, this.favorite = false, this.rating = 0}): super._();
  

@override final  ResumePointer? pointer;
@override@JsonKey() final  bool watched;
@override@JsonKey() final  bool favorite;
@override@JsonKey() final  int rating;

/// Create a copy of WatchState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WatchStateCopyWith<_WatchState> get copyWith => __$WatchStateCopyWithImpl<_WatchState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WatchState&&(identical(other.pointer, pointer) || other.pointer == pointer)&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.favorite, favorite) || other.favorite == favorite)&&(identical(other.rating, rating) || other.rating == rating));
}


@override
int get hashCode => Object.hash(runtimeType,pointer,watched,favorite,rating);

@override
String toString() {
  return 'WatchState(pointer: $pointer, watched: $watched, favorite: $favorite, rating: $rating)';
}


}

/// @nodoc
abstract mixin class _$WatchStateCopyWith<$Res> implements $WatchStateCopyWith<$Res> {
  factory _$WatchStateCopyWith(_WatchState value, $Res Function(_WatchState) _then) = __$WatchStateCopyWithImpl;
@override @useResult
$Res call({
 ResumePointer? pointer, bool watched, bool favorite, int rating
});


@override $ResumePointerCopyWith<$Res>? get pointer;

}
/// @nodoc
class __$WatchStateCopyWithImpl<$Res>
    implements _$WatchStateCopyWith<$Res> {
  __$WatchStateCopyWithImpl(this._self, this._then);

  final _WatchState _self;
  final $Res Function(_WatchState) _then;

/// Create a copy of WatchState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pointer = freezed,Object? watched = null,Object? favorite = null,Object? rating = null,}) {
  return _then(_WatchState(
pointer: freezed == pointer ? _self.pointer : pointer // ignore: cast_nullable_to_non_nullable
as ResumePointer?,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,favorite: null == favorite ? _self.favorite : favorite // ignore: cast_nullable_to_non_nullable
as bool,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of WatchState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResumePointerCopyWith<$Res>? get pointer {
    if (_self.pointer == null) {
    return null;
  }

  return $ResumePointerCopyWith<$Res>(_self.pointer!, (value) {
    return _then(_self.copyWith(pointer: value));
  });
}
}

/// @nodoc
mixin _$ProgressReport {

 FileIndex get file; double get position; double get duration; ProgressEvent get event;
/// Create a copy of ProgressReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProgressReportCopyWith<ProgressReport> get copyWith => _$ProgressReportCopyWithImpl<ProgressReport>(this as ProgressReport, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProgressReport&&(identical(other.file, file) || other.file == file)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,file,position,duration,event);

@override
String toString() {
  return 'ProgressReport(file: $file, position: $position, duration: $duration, event: $event)';
}


}

/// @nodoc
abstract mixin class $ProgressReportCopyWith<$Res>  {
  factory $ProgressReportCopyWith(ProgressReport value, $Res Function(ProgressReport) _then) = _$ProgressReportCopyWithImpl;
@useResult
$Res call({
 FileIndex file, double position, double duration, ProgressEvent event
});




}
/// @nodoc
class _$ProgressReportCopyWithImpl<$Res>
    implements $ProgressReportCopyWith<$Res> {
  _$ProgressReportCopyWithImpl(this._self, this._then);

  final ProgressReport _self;
  final $Res Function(ProgressReport) _then;

/// Create a copy of ProgressReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? file = null,Object? position = null,Object? duration = null,Object? event = null,}) {
  return _then(_self.copyWith(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FileIndex,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ProgressEvent,
  ));
}

}


/// Adds pattern-matching-related methods to [ProgressReport].
extension ProgressReportPatterns on ProgressReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProgressReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProgressReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProgressReport value)  $default,){
final _that = this;
switch (_that) {
case _ProgressReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProgressReport value)?  $default,){
final _that = this;
switch (_that) {
case _ProgressReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FileIndex file,  double position,  double duration,  ProgressEvent event)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProgressReport() when $default != null:
return $default(_that.file,_that.position,_that.duration,_that.event);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FileIndex file,  double position,  double duration,  ProgressEvent event)  $default,) {final _that = this;
switch (_that) {
case _ProgressReport():
return $default(_that.file,_that.position,_that.duration,_that.event);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FileIndex file,  double position,  double duration,  ProgressEvent event)?  $default,) {final _that = this;
switch (_that) {
case _ProgressReport() when $default != null:
return $default(_that.file,_that.position,_that.duration,_that.event);case _:
  return null;

}
}

}

/// @nodoc


class _ProgressReport implements ProgressReport {
  const _ProgressReport({required this.file, required this.position, required this.duration, this.event = ProgressEvent.checkpoint});
  

@override final  FileIndex file;
@override final  double position;
@override final  double duration;
@override@JsonKey() final  ProgressEvent event;

/// Create a copy of ProgressReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProgressReportCopyWith<_ProgressReport> get copyWith => __$ProgressReportCopyWithImpl<_ProgressReport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProgressReport&&(identical(other.file, file) || other.file == file)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,file,position,duration,event);

@override
String toString() {
  return 'ProgressReport(file: $file, position: $position, duration: $duration, event: $event)';
}


}

/// @nodoc
abstract mixin class _$ProgressReportCopyWith<$Res> implements $ProgressReportCopyWith<$Res> {
  factory _$ProgressReportCopyWith(_ProgressReport value, $Res Function(_ProgressReport) _then) = __$ProgressReportCopyWithImpl;
@override @useResult
$Res call({
 FileIndex file, double position, double duration, ProgressEvent event
});




}
/// @nodoc
class __$ProgressReportCopyWithImpl<$Res>
    implements _$ProgressReportCopyWith<$Res> {
  __$ProgressReportCopyWithImpl(this._self, this._then);

  final _ProgressReport _self;
  final $Res Function(_ProgressReport) _then;

/// Create a copy of ProgressReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? file = null,Object? position = null,Object? duration = null,Object? event = null,}) {
  return _then(_ProgressReport(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FileIndex,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ProgressEvent,
  ));
}


}

/// @nodoc
mixin _$WatchView {

 bool get watched; FileIndex get continueIndex; int get continueSeconds; List<bool> get perFile;
/// Create a copy of WatchView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WatchViewCopyWith<WatchView> get copyWith => _$WatchViewCopyWithImpl<WatchView>(this as WatchView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WatchView&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.continueIndex, continueIndex) || other.continueIndex == continueIndex)&&(identical(other.continueSeconds, continueSeconds) || other.continueSeconds == continueSeconds)&&const DeepCollectionEquality().equals(other.perFile, perFile));
}


@override
int get hashCode => Object.hash(runtimeType,watched,continueIndex,continueSeconds,const DeepCollectionEquality().hash(perFile));

@override
String toString() {
  return 'WatchView(watched: $watched, continueIndex: $continueIndex, continueSeconds: $continueSeconds, perFile: $perFile)';
}


}

/// @nodoc
abstract mixin class $WatchViewCopyWith<$Res>  {
  factory $WatchViewCopyWith(WatchView value, $Res Function(WatchView) _then) = _$WatchViewCopyWithImpl;
@useResult
$Res call({
 bool watched, FileIndex continueIndex, int continueSeconds, List<bool> perFile
});




}
/// @nodoc
class _$WatchViewCopyWithImpl<$Res>
    implements $WatchViewCopyWith<$Res> {
  _$WatchViewCopyWithImpl(this._self, this._then);

  final WatchView _self;
  final $Res Function(WatchView) _then;

/// Create a copy of WatchView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? watched = null,Object? continueIndex = null,Object? continueSeconds = null,Object? perFile = null,}) {
  return _then(_self.copyWith(
watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,continueIndex: null == continueIndex ? _self.continueIndex : continueIndex // ignore: cast_nullable_to_non_nullable
as FileIndex,continueSeconds: null == continueSeconds ? _self.continueSeconds : continueSeconds // ignore: cast_nullable_to_non_nullable
as int,perFile: null == perFile ? _self.perFile : perFile // ignore: cast_nullable_to_non_nullable
as List<bool>,
  ));
}

}


/// Adds pattern-matching-related methods to [WatchView].
extension WatchViewPatterns on WatchView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WatchView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WatchView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WatchView value)  $default,){
final _that = this;
switch (_that) {
case _WatchView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WatchView value)?  $default,){
final _that = this;
switch (_that) {
case _WatchView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool watched,  FileIndex continueIndex,  int continueSeconds,  List<bool> perFile)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WatchView() when $default != null:
return $default(_that.watched,_that.continueIndex,_that.continueSeconds,_that.perFile);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool watched,  FileIndex continueIndex,  int continueSeconds,  List<bool> perFile)  $default,) {final _that = this;
switch (_that) {
case _WatchView():
return $default(_that.watched,_that.continueIndex,_that.continueSeconds,_that.perFile);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool watched,  FileIndex continueIndex,  int continueSeconds,  List<bool> perFile)?  $default,) {final _that = this;
switch (_that) {
case _WatchView() when $default != null:
return $default(_that.watched,_that.continueIndex,_that.continueSeconds,_that.perFile);case _:
  return null;

}
}

}

/// @nodoc


class _WatchView implements WatchView {
  const _WatchView({required this.watched, required this.continueIndex, required this.continueSeconds, required final  List<bool> perFile}): _perFile = perFile;
  

@override final  bool watched;
@override final  FileIndex continueIndex;
@override final  int continueSeconds;
 final  List<bool> _perFile;
@override List<bool> get perFile {
  if (_perFile is EqualUnmodifiableListView) return _perFile;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_perFile);
}


/// Create a copy of WatchView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WatchViewCopyWith<_WatchView> get copyWith => __$WatchViewCopyWithImpl<_WatchView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WatchView&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.continueIndex, continueIndex) || other.continueIndex == continueIndex)&&(identical(other.continueSeconds, continueSeconds) || other.continueSeconds == continueSeconds)&&const DeepCollectionEquality().equals(other._perFile, _perFile));
}


@override
int get hashCode => Object.hash(runtimeType,watched,continueIndex,continueSeconds,const DeepCollectionEquality().hash(_perFile));

@override
String toString() {
  return 'WatchView(watched: $watched, continueIndex: $continueIndex, continueSeconds: $continueSeconds, perFile: $perFile)';
}


}

/// @nodoc
abstract mixin class _$WatchViewCopyWith<$Res> implements $WatchViewCopyWith<$Res> {
  factory _$WatchViewCopyWith(_WatchView value, $Res Function(_WatchView) _then) = __$WatchViewCopyWithImpl;
@override @useResult
$Res call({
 bool watched, FileIndex continueIndex, int continueSeconds, List<bool> perFile
});




}
/// @nodoc
class __$WatchViewCopyWithImpl<$Res>
    implements _$WatchViewCopyWith<$Res> {
  __$WatchViewCopyWithImpl(this._self, this._then);

  final _WatchView _self;
  final $Res Function(_WatchView) _then;

/// Create a copy of WatchView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? watched = null,Object? continueIndex = null,Object? continueSeconds = null,Object? perFile = null,}) {
  return _then(_WatchView(
watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as bool,continueIndex: null == continueIndex ? _self.continueIndex : continueIndex // ignore: cast_nullable_to_non_nullable
as FileIndex,continueSeconds: null == continueSeconds ? _self.continueSeconds : continueSeconds // ignore: cast_nullable_to_non_nullable
as int,perFile: null == perFile ? _self._perFile : perFile // ignore: cast_nullable_to_non_nullable
as List<bool>,
  ));
}


}

// dart format on
