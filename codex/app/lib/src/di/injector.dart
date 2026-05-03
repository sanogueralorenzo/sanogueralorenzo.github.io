// coverage:ignore-file
import 'dart:async';

import 'package:app/src/features/example/example_api.dart';
import 'package:app/src/network/api_type.dart';
import 'package:app/src/network/network_client_factory.dart';
import 'package:app/src/network/network_error_interceptor.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'injector.config.dart';

abstract final class Injector {
  static final _locator = GetIt.instance;
  static bool _isSetup = false;

  static void setup() {
    if (_isSetup) return;
    _locator.init();
    _isSetup = true;
  }

  static void registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    FutureOr<void> Function(T param)? dispose,
  }) {
    _locator.registerSingleton<T>(
      instance,
      instanceName: instanceName,
      dispose: dispose,
    );
  }

  static void registerLazySingleton<T extends Object>(
    T Function() factoryFunc, {
    String? instanceName,
    FutureOr<void> Function(T param)? dispose,
  }) {
    _locator.registerLazySingleton<T>(
      factoryFunc,
      instanceName: instanceName,
      dispose: dispose,
    );
  }

  static void pushNewScope({String? scopeName}) {
    _locator.pushNewScope(scopeName: scopeName);
  }

  static Future<void> popScope() {
    return _locator.popScope();
  }

  static Future<void> resetScope({bool dispose = true}) {
    return _locator.resetScope(dispose: dispose);
  }

  static T get<T extends Object>() => _locator.get();
}

@InjectableInit(asExtension: true, preferRelativeImports: true)
void configureDependencies() {}

@module
abstract class InjectorModule {
  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage();

  @lazySingleton
  SharedPreferencesAsync get sharedPreferences => SharedPreferencesAsync();

  @lazySingleton
  DeviceInfoPlugin get deviceInfo => DeviceInfoPlugin();

  @lazySingleton
  Dio dio() {
    final dio = NetworkClientFactory.createDio(apiType: ApiType.example);
    dio.interceptors.add(const NetworkErrorInterceptor());
    return dio;
  }

  @lazySingleton
  ExampleApi exampleApi(Dio dio) => ExampleApi(dio);
}
