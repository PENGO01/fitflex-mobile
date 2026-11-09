// Vendor tools · S7 around the refund screens: the sale detail (badge,
// Refunds row and Total after refunds, the Refunds card, Refund items and
// its muted reasons, Void hidden with active refunds and the void 409
// has_refunds), the sales list (badge, summary line), stock history's
// credit-note link, and the S6 reports (Refunds card, Refunds view, "Paid
// back by you" and the document status badges).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/customers/customer_profile_page.dart'
    show saleStatusBadges;
import 'package:fitflexmobile/screens/vendor/documents/document_models.dart';
import 'package:fitflexmobile/screens/vendor/documents/document_view.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_models.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_section_page.dart';
import 'package:fitflexmobile/screens/vendor/reports/reports_view.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';

import '../support/recording_api.dart';
import 'refunds_support.dart';
import 'stock_support.dart' show seedVendorHome;

Future<PageHost> pumpSale(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> tools = refundsOn,
  Map<String, dynamic>? sale,
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
}) async {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
  api.on('GET /vendor/sales/sal_1', {'sale': sale ?? refundSale()});
  return pumpPage(
    tester,
    api,
    const SaleDetailPage(saleId: 'sal_1'),
    user: user,
    lang: lang,
    size: const Size(400, 2400),
    extraRoutes: refundRoutes,
  );
}

final _partSale = refundSale(
  wheyRefunded: 1,
  wheyRefundedTzs: 3333,
  refunds: const [
    {
      'id': 'vrf_a',
      'number': 'CN-000001',
      'status': 'active',
      'refundedAt': '2026-11-03T09:00:00.000Z',
      'amountTzs': 3333,
    },
    {
      'id': 'vrf_b',
      'number': 'CN-000002',
      'status': 'reverted',
      'refundedAt': '2026-11-03T09:30:00.000Z',
      'amountTzs': 3333,
    },
  ],
);

void main() {
  setUpAll(loadAppFonts);

  group('sale detail', () {
    apiTest('no refunds: Refund items before Void; opens the refund screen', (
      tester,
      api,
    ) async {
      await pumpSale(tester, api);
      final refund = find.byKey(const Key('sale-detail-refund'));
      expect(refund, findsOneWidget);
      expect(find.byKey(const Key('sale-detail-void')), findsOneWidget);
      // Placed before Void (same row, or the row above when they wrap).
      final r = tester.getTopLeft(refund);
      final v = tester.getTopLeft(find.byKey(const Key('sale-detail-void')));
      expect(r.dy < v.dy || (r.dy == v.dy && r.dx < v.dx), isTrue);
      expect(find.byKey(const Key('sale-detail-refunds')), findsNothing);
      await tapVisible(tester, refund);
      expect(find.text('ROUTE-REFUND sal_1'), findsOneWidget);
    });

    apiTest('credit sale cleared by a credit note: Settled by credit note, '
        'like the list (UAT D2)', (tester, api) async {
      final sale = refundSale(
        kind: 'credit',
        balanceTzs: 0,
        wheyRefunded: 1,
        wheyRefundedTzs: 3333,
      )..['balanceReducedTzs'] = 3333;
      for (final lang in ['en', 'sw']) {
        final host = await pumpSale(tester, api, sale: sale, lang: lang);
        for (final k in [
          'vendor.doc.statusSettledByCreditNote',
          'vendor.refunds.badgePartial',
        ]) {
          expect(find.text(host.tr(k)), findsOneWidget, reason: '$lang $k');
        }
        expect(find.text(host.tr('vendor.sales.paidOffBadge')), findsNothing);
        // Same keys, same order as the list's rule.
        expect(
          [for (final b in saleStatusBadges(sale)) b.key],
          [
            'vendor.sales.payLaterBadge',
            'vendor.doc.statusSettledByCreditNote',
            'vendor.refunds.badgePartial',
          ],
        );
      }
    });

    apiTest('part refunded: badge, totals, card; Void hidden', (
      tester,
      api,
    ) async {
      final host = await pumpSale(tester, api, sale: _partSale);
      expect(find.text(host.tr('vendor.refunds.badgePartial')), findsOneWidget);
      expect(find.byKey(const Key('sales-receipt-refunds')), findsOneWidget);
      expect(find.text('−TSh 3,333'), findsOneWidget);
      expect(find.byKey(const Key('sales-receipt-net-after')), findsOneWidget);
      expect(find.text('TSh 16,667'), findsOneWidget);
      expect(find.text('1 refunded'), findsOneWidget);
      expect(find.byKey(const Key('sale-detail-refunds')), findsOneWidget);
      expect(find.text('CN-000001'), findsOneWidget);
      // The undone one says so in words, not only a strike-through.
      expect(
        find.text(host.tr('vendor.refunds.status.reverted')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Credit note CN-000001, TSh 3,333, .+, Refunded$'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sale-detail-void')), findsNothing);
      expect(find.text(host.tr('vendor.sales.voidHasRefunds')), findsOneWidget);
      expect(find.byKey(const Key('sale-detail-refund')), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const Key('sale-detail-refund-vrf_a')),
      );
      expect(find.text('ROUTE-REFUND-DETAIL vrf_a '), findsOneWidget);
    });

    apiTest('fully refunded: no Refund items, the muted line', (
      tester,
      api,
    ) async {
      final host = await pumpSale(
        tester,
        api,
        sale: refundSale(
          wheyRefunded: 3,
          wheyRefundedTzs: 10000,
          matRefunded: 1,
          refunds: const [
            {
              'id': 'vrf_a',
              'number': 'CN-000001',
              'status': 'active',
              'refundedAt': '2026-11-03T09:00:00.000Z',
              'amountTzs': 20000,
            },
          ],
        ),
      );
      expect(find.text(host.tr('vendor.refunds.badgeFull')), findsOneWidget);
      expect(find.byKey(const Key('sale-detail-refund')), findsNothing);
      expect(find.text(host.tr('vendor.refunds.fully')), findsOneWidget);
    });

    apiTest('refunds off: no Refund items, existing refunds still shown', (
      tester,
      api,
    ) async {
      await pumpSale(tester, api, tools: refundsOff, sale: _partSale);
      expect(find.byKey(const Key('sale-detail-refund')), findsNothing);
      expect(find.byKey(const Key('sale-detail-refunds')), findsOneWidget);
      expect(find.byKey(const Key('sales-receipt-net-after')), findsOneWidget);
    });

    apiTest('sales staff on another person\'s sale: ask the owner', (
      tester,
      api,
    ) async {
      final host = await pumpSale(
        tester,
        api,
        sale: refundSale(createdById: 'other'),
        user: const {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['sales'],
        },
      );
      expect(find.byKey(const Key('sale-detail-refund')), findsNothing);
      expect(find.text(host.tr('vendor.refunds.askOwner')), findsOneWidget);
    });

    apiTest('a void refused with has_refunds says why', (tester, api) async {
      final host = await pumpSale(tester, api);
      api.fail('POST /vendor/sales/sal_1/void', 409, {
        'error': 'has_refunds',
        'refunds': [
          {'id': 'vrf_a', 'number': 'CN-000001'},
        ],
      });
      await tapVisible(tester, find.byKey(const Key('sale-detail-void')));
      await typeInto(tester, find.byKey(const Key('sale-void-reason')), 'Oops');
      await tapVisible(tester, find.byKey(const Key('sale-void-confirm')));
      expect(find.text(host.tr('vendor.sales.voidHasRefunds')), findsOneWidget);
    });
  });

  apiTest('sales list: refund badges and the summary line', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: [], tools: refundsOn);
    api.on('GET /vendor/sales', {
      'sales': [
        {
          'id': 'sal_1',
          'number': 'R-000123',
          'soldAt': '2026-11-03T08:00:00.000Z',
          'recordedAt': '2026-11-03T08:00:00.000Z',
          'status': 'completed',
          'totalTzs': 20000,
          'itemCount': 4,
          'methods': ['cash'],
          'createdBy': {'id': 'v1', 'name': 'Owner'},
          'refundedTzs': 3333,
          'refundState': 'partial',
        },
      ],
      'nextCursor': null,
      'summary': {
        'count': 1,
        'totalTzs': 20000,
        'voidedCount': 0,
        'discountTzs': 0,
        'byMethod': [
          {'method': 'cash', 'amountTzs': 20000},
        ],
        'refundCount': 1,
        'refundTzs': 3333,
        'netTzs': 16667,
        'refundsByMethod': [
          {'method': 'cash', 'amountTzs': 3333},
        ],
      },
    });
    final host = await pumpPage(
      tester,
      api,
      const VendorHomePage(open: 'sales'),
      user: ownerUser,
      size: const Size(400, 1400),
    );
    expect(find.byKey(const Key('sales-row-refund-sal_1')), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.badgePartial')), findsOneWidget);
    expect(
      find.text('Refunds −TSh 3,333 · after refunds TSh 16,667'),
      findsOneWidget,
    );
  });

  group('reports', () {
    Map<String, dynamic> summary() => {
      'from': '2026-11-01',
      'to': '2026-11-30',
      'hasEverSold': true,
      'channels': {'walkIn': true},
      'sales': {
        'grossTzs': 20000,
        'discountTzs': 0,
        'refundTzs': 3333,
        'netTzs': 16667,
        'saleCount': 1,
        'orderCount': 0,
        'itemsSold': 4,
        'buckets': [],
      },
      'topProducts': [],
      'slowCount': 0,
      'methods': {
        'byYou': [
          {'method': 'cash', 'amountTzs': 20000, 'count': 1, 'sharePct': 100},
        ],
        'viaFitFlex': [],
        'paidBack': [
          {'method': 'cash', 'amountTzs': 3333, 'count': 1},
        ],
      },
    };
    Map<String, dynamic> refundsReport({bool empty = false}) => {
      'from': '2026-11-01',
      'to': '2026-11-30',
      'hasEverSold': true,
      'rows': empty
          ? []
          : [
              {
                'type': 'refund',
                'refundId': 'vrf_a',
                'number': 'CN-000001',
                'at': '2026-11-03T09:00:00.000Z',
                'date': '2026-11-03',
                'saleId': 'sal_1',
                'saleNumber': 'R-000123',
                'amountTzs': 6666,
                'paidOutTzs': 6666,
                'balanceReducedTzs': 0,
                'method': 'cash',
                'restockedUnits': 2,
                'status': 'reverted',
              },
              {
                'type': 'revert',
                'refundId': 'vrf_a',
                'number': 'CN-000001',
                'at': '2026-11-03T10:00:00.000Z',
                'date': '2026-11-03',
                'saleId': 'sal_1',
                'saleNumber': 'R-000123',
                'amountTzs': -6666,
                'paidOutTzs': -6666,
                'balanceReducedTzs': 0,
                'method': 'cash',
                'restockedUnits': -2,
                'status': 'reverted',
              },
            ],
      'totals': {
        'count': empty ? 0 : 1,
        'amountTzs': 0,
        'paidOutTzs': 0,
        'balanceReducedTzs': 0,
        'restockedUnits': 0,
        'revertedCount': empty ? 0 : 1,
      },
    };
    const reportTools = VendorTools(
      reports: true,
      walkInSales: true,
      refunds: true,
    );

    apiTest('the Refunds card and "Paid back by you"', (tester, api) async {
      api.on('GET /vendor/reports/summary', summary());
      api.on('GET /vendor/reports/refunds', refundsReport());
      final host = await pumpPage(
        tester,
        api,
        VendorReportsView(
          access: ReportAccess.of(reportTools, (_) => true),
          now: DateTime.utc(2026, 11, 3, 12),
        ),
        size: const Size(420, 3000),
        extraRoutes: refundRoutes,
      );
      expect(find.byKey(const Key('reports-card-refunds')), findsOneWidget);
      expect(
        find.byKey(const Key('reports-methods-paid-back')),
        findsOneWidget,
      );
      expect(
        find.text(host.tr('vendor.reports.methods.paidBack')),
        findsOneWidget,
      );
    });

    apiTest('summary.refunds fills the card: no extra report call', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/summary', {
        ...summary(),
        'refunds': {
          'count': 2,
          'amountTzs': 9999,
          'paidOutTzs': 6666,
          'balanceReducedTzs': 3333,
        },
      });
      await pumpPage(
        tester,
        api,
        VendorReportsView(
          access: ReportAccess.of(reportTools, (_) => true),
          now: DateTime.utc(2026, 11, 3, 12),
        ),
        size: const Size(420, 3000),
        keepRequests: true,
      );
      expect(find.byKey(const Key('reports-card-refunds')), findsOneWidget);
      expect(find.text('TSh\u00A09,999'), findsOneWidget);
      expect(api.sent('GET', '/vendor/reports/refunds'), isFalse);
    });

    apiTest('refunds off and summary.refunds empty: no card', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/summary', {
        ...summary(),
        'refunds': {
          'count': 0,
          'amountTzs': 0,
          'paidOutTzs': 0,
          'balanceReducedTzs': 0,
        },
      });
      await pumpPage(
        tester,
        api,
        VendorReportsView(
          access: ReportAccess.of(
            const VendorTools(reports: true, walkInSales: true),
            (_) => true,
          ),
          now: DateTime.utc(2026, 11, 3, 12),
        ),
        size: const Size(420, 3000),
        keepRequests: true,
      );
      expect(find.byKey(const Key('reports-card-refunds')), findsNothing);
      expect(api.sent('GET', '/vendor/reports/refunds'), isFalse);
    });

    apiTest('refunds off and no refund rows: no Refunds card', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/summary', summary());
      api.on('GET /vendor/reports/refunds', refundsReport(empty: true));
      await pumpPage(
        tester,
        api,
        VendorReportsView(
          access: ReportAccess.of(
            const VendorTools(reports: true, walkInSales: true),
            (_) => true,
          ),
          now: DateTime.utc(2026, 11, 3, 12),
        ),
        size: const Size(420, 3000),
      );
      expect(find.byKey(const Key('reports-card-refunds')), findsNothing);
    });

    apiTest('the Refunds view lists refunds and undos (negative)', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', {...refundsOn, 'reports': true});
      api.on('GET /vendor/reports/refunds', refundsReport());
      final host = await pumpPage(
        tester,
        api,
        ReportSectionPage(
          section: ReportSection.refunds,
          from: '2026-11-01',
          to: '2026-11-30',
          now: DateTime.utc(2026, 11, 3, 12),
        ),
        size: const Size(420, 3000),
        extraRoutes: refundRoutes,
      );
      expect(find.byKey(const Key('reports-refunds-totals')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.reports.refunds.type.refund')),
        findsOneWidget,
      );
      expect(
        find.text(host.tr('vendor.reports.refunds.type.revert')),
        findsWidgets,
      );
      expect(find.text('−TSh 6,666'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const Key('reports-refund-row-vrf_a-refund')),
      );
      expect(find.text('ROUTE-REFUND-DETAIL vrf_a '), findsOneWidget);
    });
  });

  group('document status (S7)', () {
    for (final (status, en, sw) in const [
      ('refunded', 'Refunded', 'Imerejeshwa yote'),
      (
        'settled_by_credit_note',
        'Settled by credit note',
        'Deni limefutwa kwa hati ya marejesho',
      ),
    ]) {
      apiTest('a sale document "$status" has its badge', (tester, api) async {
        for (final lang in ['en', 'sw']) {
          final locale = FFLocale()..set(Locale(lang));
          await pumpPage(
            tester,
            api,
            VendorDocumentView(
              doc: VendorDoc.fromJson({
                'docType': 'receipt',
                'number': 'R-000123',
                'status': status,
                'lines': const [],
              }),
              t: locale.t,
              lang: lang,
            ),
            lang: lang,
          );
          expect(find.text(lang == 'en' ? en : sw), findsOneWidget);
        }
      });
    }
  });
}
