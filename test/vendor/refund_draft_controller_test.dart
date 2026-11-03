// Vendor tools · S7: the refund rules without widgets — the preview mirrors
// the server's rounding (M-2..M-4: AC-6, AC-16, AC-17), the request never
// carries an amount, the M2 mirror (who may refund / undo), error words,
// VendorTools.refunds failing closed, the notification links, the credit
// note text and EN/SW parity of every S7 string.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/sales/refunds/refund_models.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';

import 'refunds_support.dart';

RefundableLine wheyLine({int refunded = 0, int refundedTzs = 0}) =>
    RefundableLine(
      saleLineId: 'sln_a',
      name: 'Whey',
      qty: 3,
      lineNetTzs: 10000,
      refundedQty: refunded,
      refundedTzs: refundedTzs,
    );

void main() {
  group('previewRefund (M-2 cumulative rounding)', () {
    test('AC-6: 1 + 1 + 1 of a TSh 10,000 line = 3,333 / 3,333 / 3,334', () {
      expect(previewRefund([wheyLine()], {'sln_a': 1}).totalTzs, 3333);
      expect(
        previewRefund(
          [wheyLine(refunded: 1, refundedTzs: 3333)],
          {'sln_a': 1},
        ).totalTzs,
        3333,
      );
      expect(
        previewRefund(
          [wheyLine(refunded: 2, refundedTzs: 6666)],
          {'sln_a': 1},
        ).totalTzs,
        3334,
      );
    });

    test('refunding everything returns exactly the line net', () {
      expect(previewRefund([wheyLine()], {'sln_a': 3}).totalTzs, 10000);
    });

    test('an undo in the middle never lets a later refund go over', () {
      // Refund A (2 units = 6,666) undone; refund B (1 unit = 3,334 after
      // A) stays: a = 1, A = 3,334. Two more units take the rest exactly.
      final p = previewRefund(
        [wheyLine(refunded: 1, refundedTzs: 3334)],
        {'sln_a': 2},
      );
      expect(p.totalTzs, 10000 - 3334);
    });

    test('picks above what is refundable are capped', () {
      final p = previewRefund(
        [wheyLine(refunded: 2, refundedTzs: 6666)],
        {'sln_a': 5},
      );
      expect(p.totalTzs, 3334);
    });

    test('AC-16: a credit refund within the balance gives nothing back', () {
      final p = previewRefund(
        [
          const RefundableLine(
            saleLineId: 'l',
            name: 'Bike',
            qty: 3,
            lineNetTzs: 90000,
          ),
        ],
        {'l': 1},
        credit: true,
        balanceTzs: 50000,
      );
      expect(p.totalTzs, 30000);
      expect(p.balanceReducedTzs, 30000);
      expect(p.paidOutTzs, 0);
    });

    test('AC-17: past the balance, the rest is paid back', () {
      final p = previewRefund(
        [
          const RefundableLine(
            saleLineId: 'l',
            name: 'Bike',
            qty: 2,
            lineNetTzs: 80000,
          ),
        ],
        {'l': 1},
        credit: true,
        balanceTzs: 20000,
      );
      expect(p.totalTzs, 40000);
      expect(p.balanceReducedTzs, 20000);
      expect(p.paidOutTzs, 20000);
    });

    test('a cash sale never reduces a balance', () {
      final p = previewRefund([wheyLine()], {'sln_a': 1}, balanceTzs: 5000);
      expect(p.balanceReducedTzs, 0);
      expect(p.paidOutTzs, 3333);
    });
  });

  group('RefundDraftController', () {
    RefundDraftController draft({bool credit = false, int balance = 0}) =>
        RefundDraftController(
          lines: [
            wheyLine(),
            const RefundableLine(
              saleLineId: 'sln_b',
              name: 'Mat',
              qty: 1,
              lineNetTzs: 10000,
            ),
          ],
          credit: credit,
          balanceTzs: balance,
          defaultMethod: 'mpesa',
        );

    test('steppers stay within 0..refundable; restock defaults on', () {
      final d = draft();
      for (var i = 0; i < 5; i++) {
        d.increment('sln_a');
      }
      expect(d.qtyOf('sln_a'), 3);
      d.decrement('sln_b');
      expect(d.qtyOf('sln_b'), 0);
      expect(d.restockOf('sln_a'), isTrue);
    });

    test('Review is blocked by the first missing thing', () {
      final d = draft();
      expect(d.problem, RefundProblem.selectSome);
      d.increment('sln_a');
      expect(d.problem, RefundProblem.reasonMissing);
      d.setReason('ok');
      expect(d.problem, RefundProblem.reasonMissing);
      d.setReason('Returned');
      // M-Pesa (the sale's method) needs its reference.
      expect(d.problem, RefundProblem.referenceRequired);
      d.setReference('QX2');
      expect(d.problem, isNull);
      expect(d.canReview, isTrue);
      d.setReference('');
      d.setMethod('cash');
      expect(d.canReview, isTrue);
    });

    test('the request names lines, never an amount; the key is kept', () {
      final d = draft()
        ..refundAll()
        ..setRestock('sln_b', false)
        ..setReason('  Changed their mind  ')
        ..setMethod('cash');
      final body = d.requestBody(makeClientRef: () => 'rfd_fixed_000001');
      expect(body, {
        'clientRef': 'rfd_fixed_000001',
        'lines': [
          {'saleLineId': 'sln_a', 'qty': 3, 'restock': true},
          {'saleLineId': 'sln_b', 'qty': 1, 'restock': false},
        ],
        'reason': 'Changed their mind',
        'method': 'cash',
      });
      expect(body.toString(), isNot(contains('Tzs')));
      // A retry reuses the key; a change drops it.
      expect(d.requestBody()['clientRef'], 'rfd_fixed_000001');
      d.decrement('sln_a');
      expect(d.clientRef, isNull);
    });

    test('nothing paid back: no method is asked or sent', () {
      final d = draft(credit: true, balance: 50000)
        ..increment('sln_a')
        ..setReason('Returned');
      expect(d.needsMethod, isFalse);
      expect(d.problem, isNull);
      expect(d.requestBody().containsKey('method'), isFalse);
    });

    test('after 409 refund_exceeds_sold the picks are clamped', () {
      final d = draft()..refundAll();
      final lowered = d.replaceLines([
        wheyLine(refunded: 2, refundedTzs: 6666),
        const RefundableLine(
          saleLineId: 'sln_b',
          name: 'Mat',
          qty: 1,
          lineNetTzs: 10000,
          refundedQty: 1,
          refundedTzs: 10000,
        ),
      ]);
      expect(lowered, {'sln_a', 'sln_b'});
      expect(d.qtyOf('sln_a'), 1);
      expect(d.qtyOf('sln_b'), 0);
    });

    test('a new key is 128 random bits the server accepts', () {
      final ref = newRefundClientRef();
      expect(ref, matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
      expect(ref, isNot(newRefundClientRef()));
    });

    test('default method: the sale\'s first payment, else cash', () {
      expect(defaultRefundMethod(refundSale()), 'mpesa');
      expect(defaultRefundMethod(refundSale(kind: 'credit')), 'cash');
    });
  });

  group('M2 mirror (Q-1)', () {
    final now = DateTime.utc(2026, 11, 3, 12);
    const staff = {
      'id': 's1',
      'userType': 'vendor_staff',
      'vendorPermissions': ['sales'],
    };

    test('owner and admin staff: any sale', () {
      expect(
        refundBlockFor(
          ownerUser,
          servedById: 'x',
          soldAt: '2026-01-01T00:00:00Z',
          now: now,
        ),
        RefundBlock.none,
      );
      expect(
        refundBlockFor(
          {...staff, 'vendorRole': 'admin'},
          servedById: 'x',
          soldAt: '2026-01-01T00:00:00Z',
          now: now,
        ),
        RefundBlock.none,
      );
    });

    test('sales staff: own sale today only', () {
      expect(
        refundBlockFor(
          staff,
          servedById: 's1',
          soldAt: '2026-11-03T06:00:00Z',
          now: now,
        ),
        RefundBlock.none,
      );
      expect(
        refundBlockFor(
          staff,
          servedById: 'x',
          soldAt: '2026-11-03T06:00:00Z',
          now: now,
        ),
        RefundBlock.askOwner,
      );
      expect(
        refundBlockFor(
          staff,
          servedById: 's1',
          soldAt: '2026-11-02T06:00:00Z',
          now: now,
        ),
        RefundBlock.askOwner,
      );
      expect(
        refundBlockFor(
          const {'id': 's2', 'userType': 'vendor_staff'},
          servedById: 's2',
          soldAt: '2026-11-03T06:00:00Z',
          now: now,
        ),
        RefundBlock.noAccess,
      );
    });

    test('undo: own refund the same EAT day; never twice', () {
      final mine = RefundRecord.fromJson(
        refundJson(createdById: 's1', refundedAt: '2026-11-03T06:00:00Z'),
      );
      final old = RefundRecord.fromJson(
        refundJson(createdById: 's1', refundedAt: '2026-11-02T06:00:00Z'),
      );
      expect(canRevertRefund(staff, mine, now: now), isTrue);
      expect(canRevertRefund(staff, old, now: now), isFalse);
      expect(canRevertRefund(ownerUser, old, now: now), isTrue);
      expect(
        canRevertRefund(
          ownerUser,
          RefundRecord.fromJson(refundJson(status: 'reverted')),
          now: now,
        ),
        isFalse,
      );
    });
  });

  test('error words: never the raw code', () {
    expect(refundErrorKey('refund_exceeds_sold'), 'vendor.refunds.err.exceeds');
    expect(refundErrorKey('revert_not_allowed'), 'vendor.refunds.askOwner');
    expect(refundErrorKey('rate_limited'), 'vendor.refunds.err.rateLimited');
    expect(refundErrorKey('weird_code'), 'vendor.refunds.err.server');
  });

  group('VendorTools.refunds', () {
    test('exactly true, and walk-in sales too, else off', () {
      expect(VendorTools.fromOptions(refundsOn).refundsOn, isTrue);
      expect(VendorTools.fromOptions(refundsOff).refundsOn, isFalse);
      expect(
        VendorTools.fromOptions({
          'refunds': true,
          'walkInSales': false,
        }).refundsOn,
        isFalse,
      );
      expect(
        VendorTools.fromOptions({
          'refunds': 'true',
          'walkInSales': true,
        }).refunds,
        isFalse,
      );
      expect(VendorTools.fromOptions(const {}).refunds, isFalse);
      expect(VendorTools.off.refundsOn, isFalse);
    });
  });

  group('notification links', () {
    test('a refund or its undo opens the refund; ids are checked', () {
      for (final type in ['vendor_sale_refunded', 'vendor_refund_reverted']) {
        expect(partnerLinkFor(side: 'vendor', type: type), 'refund');
        expect(
          partnerRouteFor(
            side: 'vendor',
            type: type,
            refundId: 'vrf_0123456789abcdef',
            saleId: 'sal_1',
          ),
          '/vendor/refunds/vrf_0123456789abcdef',
        );
        expect(
          partnerRouteFor(
            side: 'vendor',
            type: type,
            refundId: '../x',
            saleId: 'sal_1',
          ),
          '/vendor/sales/sal_1',
        );
        expect(
          partnerRouteFor(side: 'vendor', type: type),
          '/vendor/home?open=sales',
        );
      }
      expect(FFLocale.textOf('en', 'inbox.open.refund'), isNotNull);
    });
  });

  test('credit note text (§6.4): EN and SW', () {
    final r = RefundRecord.fromJson(refundJson(amount: 45000));
    String text(String lang) => creditNoteShareText(
      r,
      t: (k) => (FFLocale()..set(Locale(lang))).t(k),
      lang: lang,
      method: (m) => m == 'cash' ? (lang == 'sw' ? 'Taslimu' : 'Cash') : '$m',
      business: 'Dar Gear',
    );
    final en = text('en');
    expect(en, contains('Credit note CN-000004'));
    expect(en, contains('For receipt R-000123'));
    expect(en, contains('1 x Whey'));
    expect(en, contains('Refund total'));
    expect(en, contains('Paid back by Cash'));
    expect(en, contains('Refund given by Dar Gear.'));
    expect(en, isNot(contains('Customer returned it')));
    final sw = text('sw');
    expect(sw, contains('Hati ya marejesho CN-000004'));
    expect(sw, contains('Kwa risiti R-000123'));
    expect(sw, contains('Jumla ya marejesho'));
    // A pay-later refund names the invoice and the balance taken off.
    final credit = creditNoteShareText(
      RefundRecord.fromJson(
        refundJson(kind: 'credit', amount: 30000, balanceReduced: 30000),
      ),
      t: (k) => (FFLocale()..set(const Locale('en'))).t(k),
      lang: 'en',
      method: (m) => '$m',
    );
    expect(credit, contains('For invoice INV-000045'));
    expect(credit, contains('Taken off the balance'));
  });

  test('every S7 string has English and Swahili', () {
    final en = FFLocale.keysOf('en');
    final sw = FFLocale.keysOf('sw');
    final s7 = en.where(
      (k) =>
          k.startsWith('vendor.refunds.') ||
          k.startsWith('vendor.reports.refunds.') ||
          const {
            'vendor.sales.voidHasRefunds',
            'vendor.sales.refundsLine',
            'vendor.doc.forReceipt',
            'vendor.doc.forInvoice',
            'vendor.doc.statusIssued',
            'vendor.doc.statusRefunded',
            'vendor.doc.statusSettledByCreditNote',
            'vendor.doc.refundTotal',
            'vendor.doc.nothingPaidBack',
            'vendor.doc.refundGivenBy',
            'vendor.doc.totalAfterRefunds',
            'vendor.stock.reason.refund_restock',
            'vendor.stock.reason.refund_revert',
            'vendor.stock.creditNote',
            'vendor.reports.view.refunds',
            'vendor.reports.methods.paidBack',
            'vendor.reports.cust.refundedOff',
            'inbox.open.refund',
          }.contains(k),
    );
    expect(s7.length, greaterThan(90));
    for (final k in s7) {
      expect(sw, contains(k), reason: 'missing Swahili for $k');
      expect(
        FFLocale.textOf('sw', k),
        isNot(FFLocale.textOf('en', k)),
        reason: 'English left in Swahili for $k',
      );
    }
  });
}
