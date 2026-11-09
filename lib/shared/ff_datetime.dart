// Dates in the app's selected language, for code that formats with `intl`.
//
// [FFLocale] calls [useDateLanguage] whenever the language changes, so a
// plain `DateFormat('d MMM')` anywhere in the app follows the app language
// rather than always printing English names. Calls that already pass the
// language (`DateFormat('d MMM', lang)`) are unaffected.
//
// Times of day and the helpers that take a `locale` live in `formatters.dart`
// (`formatTimeOfDay`, `formatDate`, `context.localDayTime`, ...); use those
// first. This file is pure Dart so model files can use it too.

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

bool _symbolsLoaded = false;

/// Makes `intl` format dates in [languageCode] ('en' or 'sw') by default.
void useDateLanguage(String languageCode) {
  if (!_symbolsLoaded) {
    // Loads the bundled symbols synchronously; the returned future is done.
    initializeDateFormatting();
    _symbolsLoaded = true;
  }
  Intl.defaultLocale = languageCode;
}

/// The language dates are currently shown in: 'sw' or 'en'. For helpers
/// that have no [BuildContext] to read the app language from.
String get dateLanguage =>
    (Intl.defaultLocale ?? 'en').startsWith('sw') ? 'sw' : 'en';

/// "Oct" / "Okt" for [month] 1–12.
String shortMonthName(int month) =>
    DateFormat('MMM').format(DateTime(2000, month));

/// "October 2026" / "Oktoba 2026".
String monthAndYear(int year, int month) =>
    DateFormat('MMMM y').format(DateTime(year, month));

/// The full day name for an English weekday name as the server sends it
/// ("monday"), or null when [day] is not a weekday name.
String? weekdayName(String day) {
  const days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final i = days.indexOf(day.toLowerCase());
  if (i < 0) return null;
  // 1 January 2024 was a Monday.
  return DateFormat('EEEE').format(DateTime(2024, 1, 1 + i));
}
