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
/// abstract class LoginState extends MavericksState<LoginState>
///     with _$LoginState {
///   const LoginState._() : super();
///
///   const factory LoginState({
///     @Default('') String email,
///     @Default('') String password,
///     @Default(false) bool isPasswordVisible,
///     @Default(Uninitialized<User>()) Async<User> loginRequest,
///   }) = _LoginState;
///
///   bool get isLoginButtonVisible => email.isNotEmpty && password.isNotEmpty;
///
///   String? get errorMessage => loginRequest.errorOrNull.messageOrNull;
///
///   bool get shouldNavigateToHome => loginRequest is Success<User>;
/// }
/// ```
abstract class MavericksState<S extends MavericksState<S>> {
  const MavericksState();
}
