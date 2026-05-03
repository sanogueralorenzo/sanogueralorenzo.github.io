import 'package:app/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

extension L10nBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
