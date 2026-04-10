import 'package:injectable/injectable.dart';
import 'package:super_overlay/features/login/data/login_api.dart';
import 'package:super_overlay/features/login/data/login_models.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

abstract interface class LoginRepository {
  Future<LoginResponse> login({
    required String email,
    required String password,
  });
}

@LazySingleton(as: LoginRepository)
class LoginRepositoryImpl implements LoginRepository {
  LoginRepositoryImpl({required this.loginApi});

  final LoginApi loginApi;

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) {
    if (!_emailPattern.hasMatch(email)) {
      throw Exception('Please enter a valid email address.');
    }

    if (password.isEmpty) {
      throw Exception('Please enter your password.');
    }

    final request = LoginRequest(email: email, password: password);
    return loginApi.login(request.toJson());
  }
}
