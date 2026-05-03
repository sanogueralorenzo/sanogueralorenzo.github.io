// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'example_view_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExampleState {

 Async<ExampleTodo> get todo;
/// Create a copy of ExampleState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExampleStateCopyWith<ExampleState> get copyWith => _$ExampleStateCopyWithImpl<ExampleState>(this as ExampleState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExampleState&&(identical(other.todo, todo) || other.todo == todo));
}


@override
int get hashCode => Object.hash(runtimeType,todo);

@override
String toString() {
  return 'ExampleState(todo: $todo)';
}


}

/// @nodoc
abstract mixin class $ExampleStateCopyWith<$Res>  {
  factory $ExampleStateCopyWith(ExampleState value, $Res Function(ExampleState) _then) = _$ExampleStateCopyWithImpl;
@useResult
$Res call({
 Async<ExampleTodo> todo
});




}
/// @nodoc
class _$ExampleStateCopyWithImpl<$Res>
    implements $ExampleStateCopyWith<$Res> {
  _$ExampleStateCopyWithImpl(this._self, this._then);

  final ExampleState _self;
  final $Res Function(ExampleState) _then;

/// Create a copy of ExampleState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? todo = null,}) {
  return _then(_self.copyWith(
todo: null == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as Async<ExampleTodo>,
  ));
}

}


/// Adds pattern-matching-related methods to [ExampleState].
extension ExampleStatePatterns on ExampleState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExampleState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExampleState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExampleState value)  $default,){
final _that = this;
switch (_that) {
case _ExampleState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExampleState value)?  $default,){
final _that = this;
switch (_that) {
case _ExampleState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Async<ExampleTodo> todo)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExampleState() when $default != null:
return $default(_that.todo);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Async<ExampleTodo> todo)  $default,) {final _that = this;
switch (_that) {
case _ExampleState():
return $default(_that.todo);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Async<ExampleTodo> todo)?  $default,) {final _that = this;
switch (_that) {
case _ExampleState() when $default != null:
return $default(_that.todo);case _:
  return null;

}
}

}

/// @nodoc


class _ExampleState extends ExampleState {
  const _ExampleState({this.todo = const Uninitialized<ExampleTodo>()}): super._();
  

@override@JsonKey() final  Async<ExampleTodo> todo;

/// Create a copy of ExampleState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExampleStateCopyWith<_ExampleState> get copyWith => __$ExampleStateCopyWithImpl<_ExampleState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExampleState&&(identical(other.todo, todo) || other.todo == todo));
}


@override
int get hashCode => Object.hash(runtimeType,todo);

@override
String toString() {
  return 'ExampleState(todo: $todo)';
}


}

/// @nodoc
abstract mixin class _$ExampleStateCopyWith<$Res> implements $ExampleStateCopyWith<$Res> {
  factory _$ExampleStateCopyWith(_ExampleState value, $Res Function(_ExampleState) _then) = __$ExampleStateCopyWithImpl;
@override @useResult
$Res call({
 Async<ExampleTodo> todo
});




}
/// @nodoc
class __$ExampleStateCopyWithImpl<$Res>
    implements _$ExampleStateCopyWith<$Res> {
  __$ExampleStateCopyWithImpl(this._self, this._then);

  final _ExampleState _self;
  final $Res Function(_ExampleState) _then;

/// Create a copy of ExampleState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? todo = null,}) {
  return _then(_ExampleState(
todo: null == todo ? _self.todo : todo // ignore: cast_nullable_to_non_nullable
as Async<ExampleTodo>,
  ));
}


}

// dart format on
