import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:super_overlay/features/login/data/login_api.dart';

import 'login_injector.config.dart';

final injector = GetIt.instance;

@InjectableInit(initializerName: 'initDependencies', asExtension: true)
void configureDependencies() {
  injector.initDependencies();
}

@module
abstract class LoginModule {
  @lazySingleton
  Dio dio() {
    return Dio(
      BaseOptions(
        baseUrl: 'https://api.placeholder.super-overlay.dev',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
  }

  @lazySingleton
  LoginApi loginApi(Dio dio) => LoginApi(dio);
}
