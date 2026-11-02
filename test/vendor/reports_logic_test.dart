// Vendor reports · S6 (fitflex-functions#275): the pure rules the screens
// lean on — EAT periods and presets, grouping limits, period words, the
// 12-hour report clock, gating (fail closed), days-of-cover wording, error
// mapping and bilingual coverage. No server, no widgets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/reports/report_export.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_models.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_period.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_widgets.dart'
    show labelStep, reportMoney;
import 'package:fitflexmobile/screens/vendor/reports/report_section_page.dart'
    show periodFromLink, reportSectionLink;
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  // Thursday 29 Oct 2026, 13:00 EAT.
  final now = DateTime.utc(2026, 10, 29, 10);

  group('presets (EAT calendar days)', () {
    ReportPeriod p(ReportPreset preset) =>
        ReportPeriod.preset(preset, now: now);

    test('today, yesterday, weeks Monday–Sunday, calendar months', () {
      expect(
        (p(ReportPreset.today).from, p(ReportPreset.today).to),
        (d(2026, 10, 29), d(2026, 10, 29)),
      );
      expect(p(ReportPreset.yesterday).from, d(2026, 10, 28));
      expect(
        (p(ReportPreset.thisWeek).from, p(ReportPreset.thisWeek).to),
        (d(2026, 10, 26), d(2026, 10, 29)),
      );
      expect(
        (p(ReportPreset.lastWeek).from, p(ReportPreset.lastWeek).to),
        (d(2026, 10, 19), d(2026, 10, 25)),
      );
      expect(
        (p(ReportPreset.thisMonth).from, p(ReportPreset.thisMonth).to),
        (d(2026, 10, 1), d(2026, 10, 29)),
      );
      expect(
        (p(ReportPreset.lastMonth).from, p(ReportPreset.lastMonth).to),
        (d(2026, 9, 1), d(2026, 9, 30)),
      );
      expect(ReportPeriod.initial(now: now).preset, ReportPreset.thisMonth);
      expect(p(ReportPreset.thisMonth).fromParam, '2026-10-01');
    });

    test('last month across a year boundary', () {
      final jan = ReportPeriod.preset(
        ReportPreset.lastMonth,
        now: DateTime.utc(2027, 1, 5, 9),
      );
      expect((jan.from, jan.to), (d(2026, 12, 1), d(2026, 12, 31)));
    });

    test('today follows EAT, not UTC (21:00 UTC is midnight EAT)', () {
      // 23:30 EAT on 14 Oct = 20:30 UTC; 00:30 EAT on 15 Oct = 21:30 UTC.
      expect(
        ReportPeriod.preset(
          ReportPreset.today,
          now: DateTime.utc(2026, 10, 14, 20, 30),
        ).from,
        d(2026, 10, 14),
      );
      expect(
        ReportPeriod.preset(
          ReportPreset.today,
          now: DateTime.utc(2026, 10, 14, 21, 30),
        ).from,
        d(2026, 10, 15),
      );
    });
  });

  group('grouping and limits (mirror the server)', () {
    test('auto grouping: day ≤ 31, week ≤ 182, else month', () {
      expect(autoGroupBy(31), ReportGroupBy.day);
      expect(autoGroupBy(32), ReportGroupBy.week);
      expect(autoGroupBy(182), ReportGroupBy.week);
      expect(autoGroupBy(183), ReportGroupBy.month);
    });

    test('bucket counts and the 120-bar limit', () {
      expect(
        bucketCount(d(2026, 10, 1), d(2026, 10, 31), ReportGroupBy.day),
        31,
      );
      // Thu 1 Oct .. Sat 31 Oct touches five Mondays' weeks (28 Sep .. 26 Oct).
      expect(
        bucketCount(d(2026, 10, 1), d(2026, 10, 31), ReportGroupBy.week),
        5,
      );
      expect(
        bucketCount(d(2025, 11, 1), d(2026, 10, 31), ReportGroupBy.month),
        12,
      );
      final year = ReportPeriod.custom(d(2025, 10, 30), d(2026, 10, 29));
      expect(year.days, 365);
      expect(year.allows(ReportGroupBy.day), isFalse);
      expect(year.allows(ReportGroupBy.week), isTrue);
      expect(year.allows(ReportGroupBy.month), isTrue);
    });

    test('custom ranges: 366 days at most, never after today', () {
      expect(checkRange(d(2025, 10, 29), d(2026, 10, 29), now: now), isNull);
      expect(
        checkRange(d(2025, 10, 28), d(2026, 10, 29), now: now),
        RangeProblem.tooLong,
      );
      expect(
        checkRange(d(2026, 10, 1), d(2026, 10, 30), now: now),
        RangeProblem.future,
      );
      expect(
        checkRange(d(2026, 10, 5), d(2026, 10, 1), now: now),
        RangeProblem.toBeforeFrom,
      );
    });

    test(
      'a deep link resolves to its preset, a custom range or This month',
      () {
        expect(
          periodFromLink('2026-10-26', '2026-10-29', now: now).preset,
          ReportPreset.thisWeek,
        );
        final custom = periodFromLink('2026-10-03', '2026-10-09', now: now);
        expect(custom.preset, ReportPreset.custom);
        expect(custom.from, d(2026, 10, 3));
        // Refused or broken dates fall back to This month.
        expect(
          periodFromLink('2026-10-01', '2026-11-30', now: now).preset,
          ReportPreset.thisMonth,
        );
        expect(
          periodFromLink('bad', null, now: now).preset,
          ReportPreset.thisMonth,
        );
        expect(
          reportSectionLink(ReportSection.sales, custom, 'walk_in'),
          '/vendor/reports/sales?from=2026-10-03&to=2026-10-09&channel=walk_in',
        );
      },
    );
  });

  group('words', () {
    test('periods read like the server PDF and CSV, in both languages', () {
      expect(
        periodInWords(d(2026, 10, 14), d(2026, 10, 14), 'en'),
        '14 Oct 2026',
      );
      expect(
        periodInWords(d(2026, 10, 1), d(2026, 10, 31), 'en'),
        '1–31 Oct 2026',
      );
      expect(
        periodInWords(d(2026, 10, 1), d(2026, 10, 31), 'sw'),
        '1–31 Okt 2026',
      );
      expect(
        periodInWords(d(2026, 9, 28), d(2026, 10, 4), 'en'),
        '28 Sep – 4 Oct 2026',
      );
      expect(
        periodInWords(d(2025, 12, 30), d(2026, 1, 2), 'en'),
        '30 Dec 2025 – 2 Jan 2026',
      );
    });

    test(
      'report times in EAT: English 24-hour, Swahili 12-hour + day part',
      () {
        // 11:05 UTC = 14:05 EAT.
        final t = DateTime.utc(2026, 10, 29, 11, 5);
        expect(reportTime(t, 'en'), '14:05');
        expect(reportTime(t, 'sw'), '2:05 mchana');
        // 21:30 UTC = 00:30 EAT.
        final late = DateTime.utc(2026, 10, 14, 21, 30);
        expect(reportTime(late, 'en'), '00:30');
        expect(reportTime(late, 'sw'), '12:30 usiku');
        expect(
          reportTime(DateTime.utc(2026, 10, 14, 2, 30), 'sw'),
          '5:30 asubuhi',
        );
        expect(reportTime(DateTime.utc(2026, 10, 14, 14), 'sw'), '5:00 jioni');
      },
    );
  });

  group('gating (fail closed)', () {
    bool Function(String) perms(List<String> p) => p.contains;
    const allTools = VendorTools(
      reports: true,
      canSeeCost: true,
      canSeeOrderMoney: true,
      customers: true,
      stockLedger: true,
      walkInSales: true,
    );

    test('reports off or no `reports` permission: nothing', () {
      final off = ReportAccess.of(
        const VendorTools(canSeeCost: true, stockLedger: true),
        (_) => true,
      );
      expect(off.reports, isFalse);
      expect(off.sections, isEmpty);
      final noPerm = ReportAccess.of(allTools, perms(['payments']));
      expect(noPerm.reports, isFalse);
      expect(noPerm.cost, isFalse);
      expect(noPerm.sections, isEmpty);
    });

    test('options parse: only exactly true counts', () {
      final tools = VendorTools.fromOptions({
        'reports': 'true',
        'canSeeOrderMoney': 1,
      });
      expect(tools.reports, isFalse);
      expect(tools.canSeeOrderMoney, isFalse);
      final on = VendorTools.fromOptions({
        'reports': true,
        'canSeeOrderMoney': true,
      });
      expect(on.reports, isTrue);
      expect(on.canSeeOrderMoney, isTrue);
    });

    test(
      'reports-only staff: sales, products, stock, methods — no money rights',
      () {
        final a = ReportAccess.of(
          const VendorTools(reports: true, stockLedger: true, customers: true),
          perms(['reports']),
        );
        expect(a.sections, [
          ReportSection.sales,
          ReportSection.products,
          ReportSection.stock,
          ReportSection.methods,
        ]);
        expect(a.allows(ReportSection.profit), isFalse);
        expect(a.allows(ReportSection.payouts), isFalse);
        expect(a.allows(ReportSection.customers), isFalse);
        expect(a.payments, isFalse);
      },
    );

    test('the owner sees every section; customers need the tool too', () {
      expect(
        ReportAccess.of(allTools, (_) => true).sections,
        ReportSection.values,
      );
      final noCustomersTool = ReportAccess.of(
        const VendorTools(reports: true, canSeeCost: true),
        (_) => true,
      );
      expect(noCustomersTool.allows(ReportSection.customers), isFalse);
      expect(noCustomersTool.allows(ReportSection.stock), isFalse);
      expect(noCustomersTool.allows(ReportSection.profit), isTrue);
    });
  });

  group('days of cover (Q-9; corrected AC 18)', () {
    // The server works the figure out: floor(stock × 30 ÷ units sold in the
    // last 30 days); ≤ 7 days is "soon". The app words what it is sent.
    Map<String, dynamic> serverRow(int? stock, int unitsIn30) {
      if (stock == null) {
        return {'coverState': 'untracked', 'daysOfCover': null};
      }
      if (stock <= 0) return {'coverState': 'out', 'daysOfCover': 0};
      if (unitsIn30 == 0) return {'coverState': 'none', 'daysOfCover': null};
      final days = (stock * 30) ~/ unitsIn30;
      return {'coverState': days <= 7 ? 'soon' : 'ok', 'daysOfCover': days};
    }

    test('stock 30 with 60 sold in 30 days is 15 days (not 30)', () {
      final w = coverWording(serverRow(30, 60));
      expect((w.key, w.n, w.soon), ('vendor.reports.coverDays', 15, false));
    });

    test('stock 5 with 30 sold: 5 days and Reorder soon', () {
      final w = coverWording(serverRow(5, 30));
      expect((w.key, w.n, w.soon), ('vendor.reports.coverDays', 5, true));
    });

    test('less than a day, no sales, out of stock, not tracked', () {
      final under = coverWording(serverRow(1, 60));
      expect((under.key, under.soon), ('vendor.reports.coverUnderOne', true));
      expect(coverWording(serverRow(10, 0)).key, 'vendor.reports.coverNoSales');
      expect(coverWording(serverRow(0, 9)).key, 'vendor.reports.outOfStock');
      expect(
        coverWording(serverRow(null, 9)).key,
        'vendor.reports.coverUntracked',
      );
      expect(coverWording(const {}).key, 'vendor.reports.coverUntracked');
    });
  });

  group('readers and errors', () {
    test('a missing cost key is null (hidden), never 0', () {
      expect(maybeNum({'profitTzs': 0}, 'profitTzs'), 0);
      expect(maybeNum({}, 'profitTzs'), isNull);
      expect(maybeNum({'costTzs': null}, 'costTzs'), isNull);
      expect(formatPct(12.5), '12.5%');
      expect(formatPct(null), '—');
    });

    test('payment method words', () {
      expect(
        methodKey('cash', byYou: true),
        'vendor.reports.methods.netOfChange',
      );
      expect(methodKey('cash'), 'vendor.pos.method.cash');
      expect(methodKey('mpesa'), 'payment.method.mpesa');
      expect(methodKey('halopesa'), 'vendor.pos.method.halopesa');
      expect(methodKey('selcom_x'), 'vendor.pos.method.other');
    });

    test('server errors map to what the screen does', () {
      ApiException e(int s, Map b) => ApiException(s, b);
      expect(reportFailureOf(Exception('socket')), ReportFailure.offline);
      expect(
        reportFailureOf(e(404, {'error': 'feature_disabled'})),
        ReportFailure.featureOff,
      );
      expect(
        reportFailureOf(e(403, {'error': 'cost_not_allowed'})),
        ReportFailure.noAccess,
      );
      expect(
        reportFailureOf(e(403, {'error': 'payout_not_allowed'})),
        ReportFailure.noAccess,
      );
      expect(
        reportFailureOf(e(403, {'error': 'vendor_staff_inactive'})),
        ReportFailure.staffDisabled,
      );
      expect(
        reportFailureOf(e(400, {'error': 'invalid_range', 'reason': 'future'})),
        ReportFailure.badRange,
      );
      expect(
        reportFailureOf(e(400, {'error': 'too_many_buckets', 'max': 120})),
        ReportFailure.badRange,
      );
      expect(reportFailureOf(e(500, {})), ReportFailure.failed);
      expect(
        rangeErrorKey(e(400, {'error': 'invalid_range', 'reason': 'too_long'})),
        'vendor.reports.rangeTooLong',
      );
      expect(
        rangeErrorKey(e(400, {'error': 'invalid_range', 'reason': 'future'})),
        'vendor.reports.rangeFuture',
      );
      expect(
        rangeErrorKey(e(400, {'error': 'too_many_buckets'})),
        'vendor.reports.groupTooMany',
      );
      expect(
        rangeErrorKey(e(400, {'error': 'invalid_range', 'reason': 'x'})),
        'vendor.reports.rangeInvalid',
      );
    });
  });

  group('downloads', () {
    test('rate limited: minutes rounded up, at least 1', () {
      expect(retryMinutes({'retryAfterSeconds': 0}), 1);
      expect(retryMinutes({'retryAfterSeconds': 12}), 1);
      expect(retryMinutes({'retryAfterSeconds': 60}), 1);
      expect(retryMinutes({'retryAfterSeconds': 61}), 2);
      expect(retryMinutes({'retryAfterSeconds': 180}), 3);
      expect(retryMinutes(null), 1);
    });

    test('fallback file names follow the server rule', () {
      final oct = ReportPeriod.custom(d(2026, 10, 1), d(2026, 10, 29));
      expect(
        reportFallbackFileName(
          businessName: 'Dar Fitness Gear!',
          section: ReportSection.sales,
          period: oct,
        ),
        'dar-fitness-gear_sales_2026-10-01_2026-10-29.csv',
      );
      expect(
        reportFallbackFileName(
          businessName: null,
          section: null,
          period: ReportPeriod.custom(d(2026, 10, 14), d(2026, 10, 14)),
        ),
        'vendor_report_2026-10-14.pdf',
      );
      expect(
        reportFallbackFileName(
          businessName: 'Gear',
          section: ReportSection.payouts,
          period: oct,
        ),
        'gear_marketplace-net_2026-10-01_2026-10-29.csv',
      );
      // Stock value is "as of now": dated today only.
      expect(
        reportFallbackFileName(
          businessName: 'Gear',
          section: ReportSection.stock,
          period: oct,
          now: now,
        ),
        'gear_stock-value_2026-10-29.csv',
      );
      expect(reportSlug('  Duka  la_Asha  '), 'duka-la-asha');
      expect(reportSlug('A' * 60).length, 40);
      expect(reportSlug('!!!'), 'document');
    });

    test('products CSV carries the search; other sections do not', () {
      final r = ReportExportRequest(
        period: ReportPeriod.custom(d(2026, 10, 1), d(2026, 10, 29)),
        sort: 'units',
        q: '  whey ',
      );
      expect(r.queryFor(ReportSection.products)['q'], 'whey');
      expect(r.queryFor(ReportSection.products)['sort'], 'units');
      expect(r.queryFor(ReportSection.sales).containsKey('q'), isFalse);
      expect(
        ReportExportRequest(
          period: ReportPeriod.custom(d(2026, 10, 1), d(2026, 10, 29)),
          q: 'x' * 90,
        ).queryFor(ReportSection.products)['q']!.length,
        80,
      );
    });
  });

  group('UAT fixes', () {
    test('D6/D11: money keeps sign, currency and number together', () {
      expect(reportMoney(39000), 'TSh\u00a039,000');
      expect(reportMoney(-39000), '−TSh\u00a039,000');
      expect(reportMoney(0), 'TSh\u00a00');
      expect(reportMoney(-39000), isNot(contains(' ')));
      expect(reportMoney(-39000), isNot(contains('-')));
    });

    test('D11/D12: percent always one decimal, same minus', () {
      expect(formatPct(25), '25.0%');
      expect(formatPct(27.04), '27.0%');
      expect(formatPct(-5), '−5.0%');
    });

    test('D5: chart labels thinned so whole labels fit', () {
      // 29 days at a 327px chart (375 phone minus padding): every 3rd day.
      expect(labelStep(bars: 29, width: 279, groupBy: ReportGroupBy.day), 3);
      expect(labelStep(bars: 7, width: 279, groupBy: ReportGroupBy.day), 1);
      // Week labels ("12 Oct") need more room.
      expect(labelStep(bars: 5, width: 279, groupBy: ReportGroupBy.week), 1);
      expect(labelStep(bars: 26, width: 279, groupBy: ReportGroupBy.week), 5);
      // Larger text, fewer labels.
      expect(
        labelStep(
          bars: 29,
          width: 279,
          groupBy: ReportGroupBy.day,
          textScale: 2,
        ),
        5,
      );
      expect(labelStep(bars: 1, width: 279, groupBy: ReportGroupBy.day), 1);
    });

    test('D10: every counted string has an English singular', () {
      for (final k in const [
        'salesN',
        'itemsN',
        'unitsN',
        'ordersN',
        'countTimes',
        'voided',
        'pendingSync',
        'profit.uncosted',
        'stock.costUnknown',
      ]) {
        final one = FFLocale.textOf('en', 'vendor.reports.${k}One');
        expect(one, isNotNull, reason: k);
        expect(FFLocale.textOf('sw', 'vendor.reports.${k}One'), isNotNull);
        expect(one, isNot(FFLocale.textOf('en', 'vendor.reports.$k')));
      }
      expect(FFLocale.textOf('en', 'vendor.reports.salesNOne'), '{n} sale');
      expect(FFLocale.textOf('en', 'vendor.reports.countTimesOne'), '{n} time');
    });
  });

  group('strings', () {
    test('every reports string exists in English and Swahili', () {
      final en = FFLocale.keysOf(
        'en',
      ).where((k) => k.startsWith('vendor.reports.'));
      final sw = FFLocale.keysOf(
        'sw',
      ).where((k) => k.startsWith('vendor.reports.'));
      expect(en.length, greaterThan(150));
      expect(sw.toSet(), en.toSet());
      // Swahili is written, not English left in place (except words the
      // glossary keeps: App, Stock, CSV/PDF placeholders, the dash).
      const same = {
        'vendor.reports.channel.app',
        'vendor.reports.sort.stock',
        'vendor.reports.exportCsv',
        'vendor.reports.coverUntracked',
      };
      for (final k in en) {
        if (same.contains(k)) continue;
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: '$k is not translated',
        );
      }
    });

    test('placeholders match between the languages', () {
      final re = RegExp(r'\{(\w+)\}');
      for (final k in FFLocale.keysOf(
        'en',
      ).where((k) => k.startsWith('vendor.reports.'))) {
        Set<String> names(String lang) => re
            .allMatches(FFLocale.textOf(lang, k) ?? '')
            .map((m) => m.group(1)!)
            .toSet();
        expect(names('sw'), names('en'), reason: k);
      }
    });

    test('glossary terms', () {
      final sw = FFLocale()..set(const Locale('sw'));
      expect(sw.t('vendor.reports.tab'), 'Ripoti');
      expect(sw.t('vendor.reports.commission'), 'Kamisheni');
      expect(sw.t('vendor.reports.export'), 'Pakua');
      expect(sw.t('vendor.reports.view.stock'), contains('Stock'));
      expect(sw.t('vendor.reports.channel.walkIn'), 'Dukani');
    });
  });
}
