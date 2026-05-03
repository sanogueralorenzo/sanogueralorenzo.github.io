import 'package:flutter/foundation.dart';

enum AppEnvironment { dev, qa, prod }

abstract final class Environments {
  static const _environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );

  static AppEnvironment get current {
    return switch (_environmentName) {
      'dev' => AppEnvironment.dev,
      'qa' => AppEnvironment.qa,
      'prod' => AppEnvironment.prod,
      _ => kReleaseMode ? AppEnvironment.prod : AppEnvironment.qa,
    };
  }

  static bool get isProduction => current == AppEnvironment.prod;
}
