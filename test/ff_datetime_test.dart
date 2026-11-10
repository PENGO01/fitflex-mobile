import 'package:fitflexmobile/screens/owner/members/widgets/member_format.dart';
import 'package:fitflexmobile/screens/owner/widgets/invoice_utils.dart';
import 'package:fitflexmobile/screens/owner/widgets/statement_models.dart';
import 'package:fitflexmobile/shared/ff_datetime.dart';
import 'package:fitflexmobile/shared/formatters.dart' as fmt;
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  final when = DateTime(2026, 10, 5, 17, 30); // a Monday

  group('dates follow the app language', () {
    test('English stays as it was', () {
      FFLocale();
      expect(DateFormat('EEE d MMM').format(when), 'Mon 5 Oct');
      expect(formatDate(when), '5 Oct 2026');
      expect(monthAndYear(2026, 3), 'March 2026');
      expect(statementDay('2026-10-03'), '3 Oct');
      expect(TrainerAvailability(day: 'monday', slots: []).dayLabel, 'Monday');
    });

    test('Swahili names for days and months', () {
      FFLocale().set(const Locale('sw'));
      expect(DateFormat('EEE d MMM').format(when), 'Jumatatu 5 Okt');
      expect(DateFormat('d MMM yyyy').format(when), '5 Okt 2026');
      expect(formatDate(when), '5 Okt 2026');
      expect(monthAndYear(2026, 3), 'Machi 2026');
      // Not the first three letters of "Oktoba"/"Machi".
      expect(statementDay('2026-10-03'), '3 Okt');
      expect(statementDay('2026-03-09'), '9 Mac');
      expect(statementDay('soon'), 'soon');
      expect(
        OwnerInvoice.fromJson(const {
          'id': 'i1',
          'periodStart': '2026-08-01',
        }).monthLabel,
        'Agosti 2026',
      );
      expect(
        OwnerStatement.fromJson(const {
          'id': 's1',
          'periodStartDate': '2026-12-01',
        }).monthLabel,
        'Desemba 2026',
      );
      expect(TrainerAvailability(day: 'Friday', slots: []).dayLabel, 'Ijumaa');
      expect(
        TrainerAvailability(day: '2026-10-05', slots: []).dayLabel,
        '2026-10-05',
      );
      FFLocale();
    });

    test('a new FFLocale goes back to English', () {
      FFLocale().set(const Locale('sw'));
      FFLocale();
      expect(DateFormat('MMMM').format(when), 'October');
      expect(dateLanguage, 'en');
    });
  });

  // The Swahili period words themselves are covered by RC's
  // date_formatters_test.dart (formatTimeOfDay).
  group('time of day', () {
    test('English keeps AM/PM on member screens and slots as sent', () {
      FFLocale();
      expect(formatTime(DateTime(2026, 1, 1, 8, 30)), '8:30 AM');
      expect(formatTime(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(fmt.formatSlotTime('09:00'), '09:00');
    });

    test('Swahili uses the period word on the same 12-hour digits', () {
      FFLocale().set(const Locale('sw'));
      expect(formatTime(DateTime(2026, 1, 1, 8, 30)), '8:30 asubuhi');
      expect(formatTime(when), '5:30 jioni');
      expect(fmt.formatSlotTime('09:00', locale: 'sw'), '9:00 asubuhi');
      expect(fmt.formatSlotTime('19:30', locale: 'sw'), '7:30 usiku');
      expect(fmt.formatSlotTime('soon', locale: 'sw'), 'soon');
      expect(fmt.formatSlotTime('25:00', locale: 'sw'), '25:00');
      FFLocale();
    });
  });
}
