import 'dart:ui';

import 'package:app/l10n/gen/app_localizations.dart';
import 'package:injectable/injectable.dart';

abstract interface class AppStrings {
  String get exampleRequestFailed;

  String get exampleRetry;

  String get exampleTitle;
}

@LazySingleton(as: AppStrings)
class AppStringsImpl implements AppStrings {
  @override
  String get exampleRequestFailed => lookupAppLocalizations(
    PlatformDispatcher.instance.locale,
  ).exampleRequestFailed;

  @override
  String get exampleRetry =>
      lookupAppLocalizations(PlatformDispatcher.instance.locale).exampleRetry;

  @override
  String get exampleTitle =>
      lookupAppLocalizations(PlatformDispatcher.instance.locale).exampleTitle;
}
