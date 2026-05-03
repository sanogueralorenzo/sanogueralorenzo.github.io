// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:device_info_plus/device_info_plus.dart' as _i833;
import 'package:dio/dio.dart' as _i361;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

import '../features/example/example_api.dart' as _i469;
import '../features/example/example_repository.dart' as _i504;
import '../features/example/example_view_model.dart' as _i48;
import '../l10n/app_strings.dart' as _i248;
import 'injector.dart' as _i811;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final injectorModule = _$InjectorModule();
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => injectorModule.secureStorage,
    );
    gh.lazySingleton<_i460.SharedPreferencesAsync>(
      () => injectorModule.sharedPreferences,
    );
    gh.lazySingleton<_i833.DeviceInfoPlugin>(() => injectorModule.deviceInfo);
    gh.lazySingleton<_i361.Dio>(() => injectorModule.dio());
    gh.lazySingleton<_i469.ExampleApi>(
      () => injectorModule.exampleApi(gh<_i361.Dio>()),
    );
    gh.lazySingleton<_i248.AppStrings>(() => _i248.AppStringsImpl());
    gh.lazySingleton<_i504.ExampleRepository>(
      () => _i504.ExampleRepositoryImpl(api: gh<_i469.ExampleApi>()),
    );
    gh.factory<_i48.ExampleViewModel>(
      () =>
          _i48.ExampleViewModelImpl(repository: gh<_i504.ExampleRepository>()),
    );
    return this;
  }
}

class _$InjectorModule extends _i811.InjectorModule {}
