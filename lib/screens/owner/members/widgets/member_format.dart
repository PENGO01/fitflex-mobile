// Lightweight date/relative-time formatting for member screens, in the app's
// selected language.

import '../../../../shared/ff_datetime.dart';
import '../../../../shared/formatters.dart' show formatTimeOfDay;
import '../../../../shared/i18n.dart';
import 'package:flutter/widgets.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// "8:30 AM", or "8:30 asubuhi" in Swahili.
String formatTime(DateTime dt) {
  final local = dt.toLocal();
  if (dateLanguage == 'sw') return formatTimeOfDay(local, locale: 'sw');
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  return '$h:${_two(local.minute)} $ampm';
}

/// "12 Jan 2024"
String formatDate(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day} ${shortMonthName(local.month)} ${local.year}';
}

/// "12 Jan 2024, 8:30 AM" — absolute date + time, used by the history tables.
String formatDateTime(BuildContext context, DateTime dt) {
  final local = dt.toLocal();
  return '${formatDate(local)}, ${formatTime(local)}';
}

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// "Today, 8:30 AM" / "Yesterday" / "3 days ago".
String formatRelative(
  BuildContext context,
  DateTime? dt, {
  bool withTime = true,
}) {
  if (dt == null) return '—';
  final local = dt.toLocal();
  final diff = _daysBetween(local, DateTime.now());
  if (diff <= 0) {
    return withTime
        ? '${context.tr('time.today')}, ${formatTime(local)}'
        : context.tr('time.today');
  }
  if (diff == 1) return context.tr('time.yesterday');
  return '$diff ${context.tr('time.daysAgo')}';
}
