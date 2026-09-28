import 'dart:ui';

import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/l10n/generated/app_localizations_en.dart';

/// The app's strings where there is no `BuildContext`.
///
/// Messages that come out of the data layer — a playlist that refused to save,
/// a field that has no value — still have to follow the language the listener
/// picked, so the lookup goes through the app's own locale setting rather than
/// the widget tree. A locale the app does not ship falls back to English,
/// exactly like the tray menu does.
AppLocalizations get appLocalizations {
  final configured = localeNotifier.value;
  final locale = configured ?? PlatformDispatcher.instance.locale;
  try {
    return lookupAppLocalizations(Locale(locale.languageCode));
  } catch (_) {
    return AppLocalizationsEn();
  }
}
