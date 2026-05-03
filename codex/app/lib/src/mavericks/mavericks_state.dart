/// Base type for Mavericks state.
///
/// Following the official Mavericks guidance, a state object should be the full
/// immutable model needed to render a screen immediately.
///
/// Derived values that are part of rendering should live on state as well so
/// they stay in sync with the underlying source fields.
///
/// Example:
///
/// ```dart
/// @freezed
/// abstract class ExampleState extends MavericksState<ExampleState>
///     with _$ExampleState {
///   const ExampleState._() : super();
///
///   const factory ExampleState({
///     @Default(Uninitialized<ExampleTodo>()) Async<ExampleTodo> todo,
///   }) = _ExampleState;
///
///   ExampleTodo? get loadedTodo => todo.valueOrNull;
///
///   String? get errorMessage => todo.errorOrNull.messageOrNull;
/// }
/// ```
abstract class MavericksState<S extends MavericksState<S>> {
  const MavericksState();
}
