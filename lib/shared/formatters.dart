// Shared number/currency formatting helpers. No external deps — keeps
// formatting consistent and avoids pulling in locale-dependent behaviour.

import 'package:flutter/widgets.dart';

import 'i18n.dart';

/// Formats an integer amount with thousand separators, e.g. `1234567` ->
/// `1,234,567`. Handles negative values correctly.
String formatMoney(num value) {
  final isNegative = value < 0;
  final s = value.abs().toInt().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return isNegative ? '-${buf.toString()}' : buf.toString();
}

/// Display label for an ISO currency code. Tanzanian shillings are shown as
/// "TSh" in English and Swahili (owner decision D-8, 2026-10-19); the ISO
/// code "TZS" stays in data, API fields and payment payloads. Other codes
/// are shown as given.
String currencyLabel(String? code) {
  final c = (code ?? '').trim();
  if (c.isEmpty || c.toUpperCase() == 'TZS') return 'TSh';
  return c;
}

/// Formats an amount as a currency string, e.g. `1234567` with currency
/// `TZS` -> `TSh 1,234,567`. [currency] is the ISO code (data value); it is
/// mapped to its display label with [currencyLabel].
String formatCurrency(num value, {String currency = 'TZS'}) {
  return '${currencyLabel(currency)} ${formatMoney(value)}';
}

// ---------------------------------------------------------------------------
// Dates
//
// The server sends instants in UTC ("2026-10-18T22:30:00Z"). Members see them
// on their own clock (Tanzania is EAT, UTC+3), so a check-in at 22:30Z reads
// as 01:30 on the 19th, not the 18th. Never show `split('T').first` of a UTC
// string: that is the UTC date, which is a day early late at night.
//
// Month names are kept here (CLDR en / sw abbreviations) rather than taken
// from intl, so formatting works the same in unit tests, on the web and on
// devices without waiting for locale data to load.

/// Test hook: when set, UTC instants are shifted by this offset instead of
/// the machine's own zone, so tests can pin EAT (UTC+3) on any computer.
@visibleForTesting
Duration? debugLocalOffsetOverride;

const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthsSw = [
  'Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des',
];

/// [value] (an ISO string or a [DateTime]) on the member's clock, or null
/// when it is missing or unreadable. A date with no time ("2026-10-30") is
/// already a calendar day and is kept as it is.
DateTime? localDateTime(Object? value) {
  final parsed = switch (value) {
    final DateTime d => d,
    final String s when s.trim().isNotEmpty => DateTime.tryParse(s.trim()),
    _ => null,
  };
  if (parsed == null) return null;
  if (!parsed.isUtc) return parsed;
  final offset = debugLocalOffsetOverride;
  return offset == null ? parsed.toLocal() : parsed.add(offset);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "19 Oct 2026" (sw "19 Okt 2026") on the member's clock, or [fallback].
String formatDate(
  Object? value, {
  String locale = 'en',
  String fallback = '-',
}) {
  final d = localDateTime(value);
  if (d == null) return fallback;
  final months = locale == 'sw' ? _monthsSw : _monthsEn;
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// "19 Oct" (sw "19 Okt"): a day and month, no year.
String formatDayMonth(DateTime d, {String locale = 'en'}) =>
    '${d.day} ${(locale == 'sw' ? _monthsSw : _monthsEn)[d.month - 1]}';

/// The Swahili word for the part of the day [hour] (0–23) falls in. Same
/// rule as `swahiliDayPeriod` in the Swahili structural work (mobile#62).
String _swDayPeriod(int hour) {
  if (hour >= 5 && hour < 12) return 'asubuhi';
  if (hour >= 12 && hour < 16) return 'mchana';
  if (hour >= 16 && hour < 19) return 'jioni';
  return 'usiku';
}

/// A time of day: English 24-hour "17:30"; Swahili style per the glossary
/// (owner, 2026-10-04): a 12-hour clock with the part of the day,
/// "5:30 jioni". The digits are those of a 12-hour clock, not the
/// traditional six-hour offset.
String formatTimeOfDay(DateTime d, {String locale = 'en'}) {
  if (locale == 'sw') {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${_two(d.minute)} ${_swDayPeriod(d.hour)}';
  }
  return '${_two(d.hour)}:${_two(d.minute)}';
}

/// A time slot the server sends as "HH:mm" (session and availability
/// slots): English shows it as given ("17:30"); Swahili reads "5:30 jioni"
/// like [formatTimeOfDay]. Anything that is not a time is returned unchanged.
String formatSlotTime(String hhmm, {String locale = 'en'}) {
  if (locale != 'sw') return hhmm;
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return hhmm;
  }
  return formatTimeOfDay(DateTime(2000, 1, 1, h, m), locale: locale);
}

/// "19 Oct 2026, 01:30" (sw "19 Okt 2026, 1:30 usiku") on the member's
/// clock, or [fallback].
String formatDateTime(
  Object? value, {
  String locale = 'en',
  String fallback = '-',
}) {
  final d = localDateTime(value);
  if (d == null) return fallback;
  return '${formatDate(d, locale: locale)}, '
      '${formatTimeOfDay(d, locale: locale)}';
}

const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
// CLDR sw has no shorter weekday names than the full ones.
const _weekdaysSw = [
  'Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', //
  'Ijumaa', 'Jumamosi', 'Jumapili',
];

/// "Sun 19 Oct · 17:30" (sw "Jumapili 19 Okt · 5:30 jioni") on the
/// member's clock, or [fallback]. [withYear] adds the year after the month.
/// For lists of visits, check-ins and activities, where the weekday helps.
String formatDayTime(
  Object? value, {
  String locale = 'en',
  bool withYear = false,
  String fallback = '-',
}) {
  final d = localDateTime(value);
  if (d == null) return fallback;
  final sw = locale == 'sw';
  final weekday = (sw ? _weekdaysSw : _weekdaysEn)[d.weekday - 1];
  final month = (sw ? _monthsSw : _monthsEn)[d.month - 1];
  final year = withYear ? ' ${d.year}' : '';
  return '$weekday ${d.day} $month$year · '
      '${formatTimeOfDay(d, locale: locale)}';
}

/// The same, in the language the member chose.
extension FFDateFormatting on BuildContext {
  String localDayTime(
    Object? value, {
    bool withYear = false,
    String fallback = '-',
  }) => formatDayTime(
    value,
    locale: FFLocaleScope.of(this).locale.languageCode,
    withYear: withYear,
    fallback: fallback,
  );

  String localTimeOfDay(DateTime value) => formatTimeOfDay(
    localDateTime(value) ?? value,
    locale: FFLocaleScope.of(this).locale.languageCode,
  );

  String localSlotTime(String hhmm) => formatSlotTime(
    hhmm,
    locale: FFLocaleScope.of(this).locale.languageCode,
  );

  String localDate(Object? value, {String fallback = '-'}) => formatDate(
    value,
    locale: FFLocaleScope.of(this).locale.languageCode,
    fallback: fallback,
  );

  String localDateTimeText(Object? value, {String fallback = '-'}) =>
      formatDateTime(
        value,
        locale: FFLocaleScope.of(this).locale.languageCode,
        fallback: fallback,
      );
}
