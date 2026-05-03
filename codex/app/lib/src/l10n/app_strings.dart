import 'dart:ui';

import 'package:app/l10n/gen/app_localizations.dart';
import 'package:injectable/injectable.dart';

abstract interface class AppStrings {
  String get exampleTitle;
}

@LazySingleton(as: AppStrings)
class AppStringsImpl implements AppStrings {
  @override
  String get exampleTitle =>
      lookupAppLocalizations(PlatformDispatcher.instance.locale).exampleTitle;
}
