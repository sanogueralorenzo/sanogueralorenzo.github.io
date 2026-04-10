// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:dio/dio.dart' as _i361;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:super_overlay/features/login/data/login_api.dart' as _i473;
import 'package:super_overlay/features/login/data/login_repository.dart'
    as _i301;
import 'package:super_overlay/features/login/login_injector.dart' as _i169;
import 'package:super_overlay/features/login/login_view_model.dart' as _i970;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt initDependencies({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final loginModule = _$LoginModule();
    gh.lazySingleton<_i361.Dio>(() => loginModule.dio());
    gh.lazySingleton<_i473.LoginApi>(
      () => loginModule.loginApi(gh<_i361.Dio>()),
    );
    gh.lazySingleton<_i301.LoginRepository>(
      () => _i301.LoginRepositoryImpl(loginApi: gh<_i473.LoginApi>()),
    );
    gh.factory<_i970.LoginViewModel>(
      () => _i970.LoginViewModelImpl(
        loginRepository: gh<_i301.LoginRepository>(),
      ),
    );
    return this;
  }
}

class _$LoginModule extends _i169.LoginModule {}
