// Vendor tools · S9 without widgets: the receive form's totals and checks,
// the even split (remainder on the last), the coverage preview (mirrors
// P-5), the request (never a total), the local draft (save / restore /
// cleared on sign-out), the M2 void rule, error words (incl. the #327
// review's has_others_payments), VendorTools.purchases failing closed, the
// push links, the GRN text share and EN/SW parity of every S9 string.
import 'package:fitflexmobile/screens/vendor/purchases/purchase_draft_controller.dart';
import 'package:fitflexmobile/screens/vendor/purchases/purchase_models.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/vendor_purchase_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchases_support.dart';

String en(String key) => FFLocale.textOf('en', key) ?? key;

DraftLine whey({int qty = 10, int? cost = 9500}) =>
    DraftLine(productId: 'p1', name: 'Whey 1kg', qty: qty, unitCostTzs: cost);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 3, 9); // 12:00 EAT, 3 Nov

  group('PurchaseDraftController', () {
    test('totals are qty × unit cost; empty and bad lines block Review', () {
      final d = PurchaseDraftController(now: () => now);
      expect(d.problem, 'vendor.purchases.needItem');
      d.add(whey());
      d.add(
        DraftLine(
          productId: 'p2',
          variant: 'M',
          name: 'Tee',
          qty: 2,
          unitCostTzs: 0,
        ),
      );
      expect(d.totalTzs, 95000);
      expect(d.units, 12);
      d.setQty(d.lines.first, 0);
      expect(d.problem, 'vendor.purchases.needLineFix');
      d.setQty(d.lines.first, 10);
      d.setCost(d.lines.first, null);
      expect(d.problem, 'vendor.purchases.needLineFix');
      d.dispose();
    });

    test(
      'the same product + variant is one line (duplicate_line never sent)',
      () {
        final d = PurchaseDraftController(now: () => now);
        final a = d.add(whey());
        final b = d.add(whey(qty: 3));
        expect(identical(a, b), isTrue);
        expect(d.lines, hasLength(1));
        d.add(DraftLine(productId: 'p2', variant: 'S', name: 'Tee'));
        d.add(DraftLine(productId: 'p2', variant: 'M', name: 'Tee'));
        expect(d.lines, hasLength(3));
        d.dispose();
      },
    );

    test(
      'P-3: without a supplier the default is Paid in full; owing needs one',
      () {
        final d = PurchaseDraftController(now: () => now)..add(whey());
        expect(d.payMode, PayMode.full);
        expect(d.canReview, isTrue);
        d.payMode = PayMode.none;
        expect(d.problem, 'vendor.purchases.needSupplier');
        d.supplier = {'id': 'vsp_1', 'name': 'Juma'};
        expect(d.canReview, isTrue);
        d.dispose();
      },
    );

    test('with a supplier the default is Not paid yet, due received + 30', () {
      final d = PurchaseDraftController(now: () => now)
        ..supplier = {'id': 'vsp_1', 'name': 'Juma'}
        ..add(whey());
      expect(d.payMode, PayMode.none);
      final body = d.toRequest('grn_abcdefgh');
      expect(body['dueDate'], '2026-12-03');
      expect(body.containsKey('paidNow'), isFalse);
      expect(body.containsKey('schedule'), isFalse);
      d.dispose();
    });

    test('the request never carries a total; reference for mobile money', () {
      final d = PurchaseDraftController(now: () => now)
        ..supplier = {'id': 'vsp_1', 'name': 'Juma'}
        ..add(whey(qty: 20, cost: 10000));
      d.payMode = PayMode.part;
      d.paidNowTzs = 50000;
      d.method = 'mpesa';
      d.changed();
      expect(d.problem, 'vendor.pos.referenceRequired');
      d.reference = ' QK12 ';
      d.startSplit();
      d.splitCount = 3;
      d.splitEvenly();
      expect(d.canReview, isTrue);
      final body = d.toRequest('grn_abcdefgh');
      expect(body.toString(), isNot(contains('totalTzs')));
      expect(body['paidNow'], {
        'amountTzs': 50000,
        'method': 'mpesa',
        'reference': 'QK12',
      });
      expect(body['schedule'], [
        {'dueDate': '2026-12-03', 'amountTzs': 50000},
        {'dueDate': '2027-01-03', 'amountTzs': 50000},
        {'dueDate': '2027-02-03', 'amountTzs': 50000},
      ]);
      expect(body.containsKey('dueDate'), isFalse);
      expect(body['lines'], [
        {'productId': 'p1', 'qty': 20, 'unitCostTzs': 10000},
      ]);
      d.dispose();
    });

    test('AC-16: instalments that do not add up keep Review off', () {
      final d = PurchaseDraftController(now: () => now)
        ..supplier = {'id': 'vsp_1', 'name': 'Juma'}
        ..add(whey(qty: 20, cost: 10000));
      d.startSplit();
      d.schedule.first.amountTzs -= 1;
      d.changed();
      expect(d.problem, 'vendor.purchases.sumWrong');
      d.dispose();
    });

    test('paid part must be 1 … total − 1', () {
      final d = PurchaseDraftController(now: () => now)
        ..supplier = {'id': 'vsp_1'}
        ..add(whey());
      d.payMode = PayMode.part;
      d.paidNowTzs = 95000;
      expect(d.problem, 'vendor.purchases.needPaidNow');
      d.paidNowTzs = 1000;
      d.changed();
      expect(d.canReview, isTrue);
      d.dispose();
    });

    test('cost notices: known cost, unknown cost, free, equal', () {
      final known = whey()
        ..costKnown = true
        ..currentCostTzs = 9000;
      expect(known.costChanges, isTrue);
      known.unitCostTzs = 9000;
      expect(known.costChanges, isFalse);
      final free = whey(cost: 0);
      expect(free.free, isTrue);
      expect(free.costChanges, isFalse);
      final unknown = whey();
      expect(unknown.costChanges, isTrue);
      unknown.last = const LastCost(unitCostTzs: 9500);
      expect(unknown.costChanges, isFalse);
    });

    test(
      'draft: saved after the debounce, restored without a clientRef',
      () async {
        SharedPreferences.setMockInitialValues({});
        const key = 'vendor_purchase_draft.v1.v1';
        final d = PurchaseDraftController(
          storageKey: key,
          now: () => now,
          debounce: Duration.zero,
        )..supplier = {'id': 'vsp_1', 'name': 'Juma', 'phone': '+255712'};
        d.add(whey());
        d.clientRef = 'grn_sent_once';
        await d.saveNow();
        final kept = await VendorPurchaseDraftStore.load(key);
        expect(kept, isNotNull);
        expect(kept.toString(), isNot(contains('grn_sent_once')));
        final back = PurchaseDraftController(storageKey: key, now: () => now)
          ..restore(kept!);
        expect(back.lines.single.unitCostTzs, 9500);
        expect(back.supplier?['name'], 'Juma');
        expect(back.clientRef, isNull);
        await back.discard();
        expect(await VendorPurchaseDraftStore.load(key), isNull);
        d.dispose();
        back.dispose();
      },
    );

    test(
      'Q-5: sign-out removes every kept delivery draft (cost figures)',
      () async {
        SharedPreferences.setMockInitialValues({
          'vendor_purchase_draft.v1.v1': '{"lines":[]}',
          'vendor_purchase_draft.v1.s1': '{"lines":[]}',
          'ff.locale': 'sw',
        });
        final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
        await auth.signIn('token', {'id': 'v1', 'userType': 'vendor'});
        await auth.signOut();
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((k) => k.startsWith('vendor_purchase_draft.')),
          isEmpty,
        );
        expect(prefs.getString('ff.locale'), 'sw');
      },
    );

    test('draft key per vendor and person', () {
      expect(
        VendorPurchaseDraftStore.keyFor(ownerUser),
        'vendor_purchase_draft.v1.v1',
      );
      expect(
        VendorPurchaseDraftStore.keyFor(staffUser(['purchases'])),
        'vendor_purchase_draft.v1.s1',
      );
      expect(
        VendorPurchaseDraftStore.keyFor({'id': 'm', 'userType': 'member'}),
        isNull,
      );
    });
  });

  group('scheduleFor', () {
    test('even split, the last instalment takes the remainder', () {
      final rows = scheduleFor(100000, 0, 3, '2026-12-15');
      expect(rows.map((r) => r.amountTzs), [33333, 33333, 33334]);
      expect(rows.map((r) => r.dueDate), [
        '2026-12-15',
        '2027-01-15',
        '2027-02-15',
      ]);
    });

    test('every 2 weeks; month ends clamp (31 Jan → 28 Feb)', () {
      expect(
        scheduleFor(
          10,
          0,
          2,
          '2026-11-03',
          every: PlanEvery.twoWeeks,
        ).map((r) => r.dueDate),
        ['2026-11-03', '2026-11-17'],
      );
      expect(addMonthsTo('2027-01-31', 1), '2027-02-28');
    });

    test('after a payment now; never a row under 1', () {
      expect(
        scheduleFor(200000, 50000, 3, '2026-12-03').map((r) => r.amountTzs),
        [50000, 50000, 50000],
      );
      expect(scheduleFor(2, 0, 5, '2026-12-03'), hasLength(2));
      expect(scheduleFor(100, 100, 3, '2026-12-03'), isEmpty);
    });
  });

  group('coverage preview (P-5)', () {
    test('AC-17: 70,000 covers instalment 2 and 20,000 of instalment 3', () {
      final plan = instalmentsOf(purchaseJson());
      final parts = previewCoverage(plan, 70000);
      expect(parts.map((p) => p.instalment.seq), [2, 3]);
      expect(parts.map((p) => p.amountTzs), [50000, 20000]);
      expect(parts.first.paysOff, isTrue);
      expect(parts.last.paysOff, isFalse);
    });

    test('a partly paid instalment is finished first', () {
      final plan = instalmentsOf(
        purchaseJson(
          instalments: [
            inst(1, '2026-11-03', 50000, 50000, 'paid'),
            inst(2, '2026-12-03', 50000, 20000, 'part_paid'),
            inst(3, '2027-01-03', 50000, 0, 'due'),
          ],
        ),
      );
      final parts = previewCoverage(plan, 40000);
      expect(parts.map((p) => (p.instalment.seq, p.amountTzs)), [
        (2, 30000),
        (3, 10000),
      ]);
      expect(parts.first.paysOff, isTrue);
    });

    test('instalment states in words', () {
      final i = inst(3, '2026-10-20', 50000, 20000, 'part_paid');
      expect(
        instalmentStateText(en, Instalment.fromJson(i)),
        'TSh 20,000 of TSh 50,000 paid',
      );
      expect(
        instalmentStateText(
          en,
          Instalment.fromJson(
            inst(2, '2026-10-20', 1, 0, 'overdue', daysOverdue: 14),
          ),
        ),
        'Overdue 14 days',
      );
      expect(dueText(en, '2026-11-08', '2026-11-03'), 'Due in 5 days');
      expect(dueText(en, '2026-11-03', '2026-11-03'), 'Due today');
    });
  });

  group('M2: who may void', () {
    test(
      'owner and admin staff any; other staff own record on its EAT day',
      () {
        expect(
          canVoidPurchaseRecord(
            ownerUser,
            byId: 'x',
            at: '2020-01-01T00:00:00Z',
          ),
          isTrue,
        );
        expect(
          canVoidPurchaseRecord(
            staffUser(['purchases'], role: 'admin'),
            byId: 'x',
            at: '2020-01-01T00:00:00Z',
          ),
          isTrue,
        );
        final staff = staffUser(['purchases']);
        expect(
          canVoidPurchaseRecord(
            staff,
            byId: 's1',
            at: '2026-11-03T05:00:00Z',
            now: now,
          ),
          isTrue,
        );
        expect(
          canVoidPurchaseRecord(
            staff,
            byId: 'v1',
            at: '2026-11-03T05:00:00Z',
            now: now,
          ),
          isFalse,
        );
        // 20:59 UTC on 2 Nov is 23:59 EAT on 2 Nov: yesterday.
        expect(
          canVoidPurchaseRecord(
            staff,
            byId: 's1',
            at: '2026-11-02T20:59:00Z',
            now: now,
          ),
          isFalse,
        );
        expect(
          canVoidPurchaseRecord(
            staffUser(['products']),
            byId: 's1',
            at: '2026-11-03T05:00:00Z',
            now: now,
          ),
          isFalse,
        );
      },
    );
  });

  group('error words', () {
    String text(
      String code, [
      Map<String, dynamic> extra = const {},
      String where = 'receive',
    ]) => purchaseErrorText(
      en,
      ApiException(409, {'error': code, ...extra}),
      where: where,
      name: 'Whey',
    );

    test('mapped codes, never the raw code', () {
      expect(
        text('product_unavailable'),
        "Whey can't be received any more. Remove it.",
      );
      expect(text('overpayment', {'totalTzs': 95000}), contains('TSh 95,000'));
      expect(
        text('overpayment', {'balanceTzs': 80000}, 'payment'),
        'That is more than is owed (TSh 80,000).',
      );
      expect(
        text('supplier_required', {}, 'paymentVoid'),
        en('vendor.purchases.err.noSupplierDebt'),
      );
      expect(text('supplier_required'), en('vendor.purchases.needSupplier'));
      expect(
        text('void_not_allowed', {'reason': 'not_own'}),
        en('vendor.purchases.askOwner'),
      );
      expect(
        text('void_not_allowed', {'reason': 'has_others_payments'}),
        'Ask the owner or an admin to void this; it has payments recorded by someone else.',
      );
      expect(
        text('insufficient_stock', {
          'lines': [
            {'name': 'Whey 1kg', 'receivedQty': 10, 'available': 4},
          ],
        }),
        contains('Whey 1kg: received 10, in stock 4'),
      );
      expect(
        text('schedule_mismatch', {'expectedTzs': 150000}),
        'Instalments must add up to TSh 150,000.',
      );
      expect(text('rate_limited', {'retryAfterSeconds': 12}), contains('12'));
      expect(text('purchase_not_found'), en('vendor.purchases.notFound'));
      expect(text('something_new'), en('vendor.purchases.err.server'));
    });

    test(
      'a suspended vendor reads as suspended (GET /vendor/products too)',
      () {
        expect(
          purchaseLoadErrorKey(
            ApiException(403, {'error': 'vendor_suspended'}),
          ),
          'vendor.sales.suspended',
        );
        expect(purchaseLoadErrorKey(Exception('offline')), 'error.network');
      },
    );
  });

  test('client refs never end in :paid (#327 review)', () {
    for (var i = 0; i < 20; i++) {
      final r = newPurchaseClientRef('vpay');
      expect(r, matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
      expect(r.endsWith(':paid'), isFalse);
    }
  });

  group('VendorTools.purchases', () {
    test('exactly true, else off (fail closed)', () {
      expect(VendorTools.fromOptions(purchasesOnTools).purchases, isTrue);
      expect(
        VendorTools.fromOptions(const {'purchases': 'true'}).purchases,
        isFalse,
      );
      expect(VendorTools.fromOptions(const {}).purchases, isFalse);
      expect(VendorTools.off.purchases, isFalse);
      expect(
        purchasesOn(VendorTools.fromOptions(purchasesOnTools), (_) => false),
        isFalse,
      );
    });
  });

  group('notification links', () {
    test('both void pushes open the purchase; ids are checked', () {
      for (final type in [
        'vendor_purchase_voided',
        'vendor_purchase_payment_voided',
      ]) {
        expect(partnerLinkFor(side: 'vendor', type: type), 'purchase');
        expect(
          partnerRouteFor(
            side: 'vendor',
            type: type,
            purchaseId: 'vpo_0123456789abcdef',
          ),
          '/vendor/purchases/vpo_0123456789abcdef',
        );
        expect(
          partnerRouteFor(side: 'vendor', type: type, purchaseId: '../x'),
          '/vendor/home?open=products&view=purchases',
        );
      }
      expect(FFLocale.textOf('en', 'inbox.open.purchase'), isNotNull);
      expect(FFLocale.textOf('sw', 'inbox.open.purchase'), isNotNull);
    });
  });

  group('text share', () {
    test('never the previous cost, the note or who recorded it', () {
      final text = purchaseShareText(
        purchaseJson(),
        en,
        'en',
        business: 'Dar Gear',
      );
      expect(text, contains('Dar Gear'));
      expect(text, contains('Stock received GRN-000012'));
      expect(text, contains('From Juma Supplies'));
      expect(text, contains('Supplier invoice: INV-4471'));
      expect(text, contains('20 x Whey 1kg'));
      expect(text, contains('1 x Tee (M)'));
      expect(text, contains('Left to pay'));
      expect(text, contains('Not a TRA fiscal receipt.'));
      expect(text, isNot(contains('9,000')));
      expect(text, isNot(contains('Back door')));
      expect(text, isNot(contains('Asha')));
    });

    test('Swahili words', () {
      String sw(String k) => FFLocale.textOf('sw', k) ?? k;
      final text = purchaseShareText(purchaseJson(), sw, 'sw');
      expect(text, contains('Kutoka Juma Supplies'));
      expect(text, contains('Jumla'));
      expect(text, contains('Kiasi kilichobaki'));
    });
  });

  test('every S9 string has English and Swahili', () {
    final enKeys = FFLocale.keysOf('en');
    final swKeys = FFLocale.keysOf('sw');
    final s9 = enKeys.where(
      (k) =>
          k.startsWith('vendor.purchases.') ||
          k.startsWith('vendor.suppliers.') ||
          k.startsWith('vendor.payables.') ||
          k == 'vendor.permission.purchases' ||
          k == 'vendor.permission.purchasesHint' ||
          k == 'vendor.stock.reason.stock_in' ||
          k == 'vendor.stock.reason.stock_in_void' ||
          k == 'vendor.stock.grn' ||
          k == 'vendor.reports.methods.paidToSuppliers' ||
          k == 'inbox.open.purchase',
    );
    expect(s9.length, greaterThan(200));
    for (final k in s9) {
      expect(swKeys, contains(k), reason: 'no Swahili for $k');
      expect(FFLocale.textOf('sw', k)!.trim(), isNotEmpty);
    }
    expect(
      FFLocale.textOf('sw', 'vendor.payables.youOwe'),
      contains('Unadaiwa'),
    );
  });
}
