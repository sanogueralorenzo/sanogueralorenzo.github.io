import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:super_overlay/features/login/data/login_models.dart';
import 'package:super_overlay/features/login/data/login_repository.dart';
import 'package:super_overlay/mavericks/async.dart';
import 'package:super_overlay/mavericks/mavericks_state.dart';
import 'package:super_overlay/mavericks/mavericks_view_model.dart';

part 'login_view_model.freezed.dart';

@freezed
abstract class LoginState extends MavericksState<LoginState> with _$LoginState {
  const LoginState._() : super();

  const factory LoginState({
    @Default('') String email,
    @Default('') String password,
    @Default(false) bool isPasswordVisible,
    @Default(Uninitialized<LoginResponse>()) Async<LoginResponse> loginRequest,
  }) = _LoginState;

  bool get isLoginButtonVisible => email.isNotEmpty && password.isNotEmpty;

  String? get errorMessage => loginRequest.errorOrNull.messageOrNull;

  bool get isLoggedIn => loginRequest is Success<LoginResponse>;

  String? get welcomeMessage {
    return switch (loginRequest) {
      Success<LoginResponse>(:final value) => 'Welcome ${value.user.name}',
      _ => null,
    };
  }
}

abstract class LoginViewModel extends MavericksViewModel<LoginState> {
  LoginViewModel(super.initialState);

  void updateEmail(String email);

  void updatePassword(String password);

  void togglePasswordVisibility();

  Future<void> login();
}

@Injectable(as: LoginViewModel)
class LoginViewModelImpl extends LoginViewModel {
  LoginViewModelImpl({required this.loginRepository})
    : super(const LoginState());

  final LoginRepository loginRepository;

  @override
  void updateEmail(String email) {
    setState((state) => state.copyWith(email: email));
  }

  @override
  void updatePassword(String password) {
    setState((state) => state.copyWith(password: password));
  }

  @override
  void togglePasswordVisibility() {
    setState(
      (state) => state.copyWith(isPasswordVisible: !state.isPasswordVisible),
    );
  }

  @override
  Future<void> login() {
    final email = state.email;
    final password = state.password;

    return execute<LoginResponse>(
      task: () => loginRepository.login(email: email, password: password),
      reducer: (state, request) => state.copyWith(loginRequest: request),
      current: (state) => state.loginRequest,
      retainValue: true,
    );
  }
}
