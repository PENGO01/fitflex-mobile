// Vendor tools · S9: suppliers (spec §4.6–§4.7) — list filters and sort as
// sent, empty states, the form's validation and the duplicate link, the
// profile (owed, aging, open instalments, bought line), archive disabled
// while owed, restore, and Call's label.
import 'package:fitflexmobile/screens/vendor/purchases/suppliers_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import 'purchases_support.dart';

const _sid = 'vsp_0000000000000001';

Map<String, dynamic> profileJson({int owed = 150000, bool archived = false}) =>
    {
      'supplier': {
        'id': _sid,
        'name': 'Juma Supplies',
        'phone': '+255712345678',
        'email': null,
        'contactPerson': 'Juma',
        'address': 'Kariakoo',
        'tin': '123-456-789',
        'note': null,
        'archived': archived,
        'archivedAt': archived ? '2026-11-01T00:00:00.000Z' : null,
        'createdAt': '2026-10-01T00:00:00.000Z',
        'updatedAt': '2026-10-01T00:00:00.000Z',
      },
      'totals': {
        'purchasedTzs': 400000,
        'purchaseCount': 3,
        'paidTzs': 250000,
        'lastReceivedOn': '2026-11-03',
      },
      'owedTzs': owed,
      'overdueTzs': owed > 0 ? 20000 : 0,
      'aging': {
        'current': owed > 0 ? owed - 20000 : 0,
        'd1_30': owed > 0 ? 20000 : 0,
        'd31_60': 0,
        'd61_90': 0,
        'd90plus': 0,
      },
      'asOf': '2026-11-03',
      'openInstalments': owed > 0
          ? [
              {
                'purchaseId': 'vpo_0000000000000012',
                'number': 'GRN-000012',
                'seq': 2,
                'dueDate': '2026-10-20',
                'openTzs': 20000,
                'daysOverdue': 14,
              },
            ]
          : [],
    };

void main() {
  setUpAll(loadAppFonts);

  apiTest('list: rows with what you owe; filters and sort as sent', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.on('GET /vendor/suppliers', {
      'suppliers': [
        supplierRow(_sid, 'Juma Supplies', owed: 150000, overdue: 20000),
        supplierRow('vsp_2', 'Kariakoo Traders'),
      ],
      'nextCursor': null,
    });
    final host = await pumpPage(
      tester,
      api,
      const SuppliersPage(),
      user: ownerUser,
      size: const Size(400, 1000),
      extraRoutes: purchaseRoutes,
    );
    expect(find.text('You owe TSh 150,000'), findsOneWidget);
    expect(find.text(host.tr('vendor.payables.nothingOwed')), findsOneWidget);
    expect(find.text('Overdue TSh 20,000'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('suppliers-filter-owing')));
    expect(api.requests.last.query, contains('filter=owing'));
    await tapVisible(tester, find.byKey(const Key('suppliers-sort')));
    await tester.tap(find.text(host.tr('vendor.suppliers.sort.owed')));
    await tester.pumpAndSettle();
    expect(api.requests.last.query, contains('sort=owed'));
    await tapVisible(tester, find.byKey(const Key('supplier-row-$_sid')));
    expect(find.text('ROUTE-SUPPLIER $_sid'), findsOneWidget);
  });

  apiTest('list: empty and filter-empty states', (tester, api) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.on('GET /vendor/suppliers', {'suppliers': [], 'nextCursor': null});
    await pumpPage(
      tester,
      api,
      const SuppliersPage(),
      user: ownerUser,
      extraRoutes: purchaseRoutes,
    );
    expect(find.byKey(const Key('suppliers-empty')), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const Key('suppliers-filter-archived')),
    );
    expect(find.byKey(const Key('suppliers-empty-filter')), findsOneWidget);
  });

  apiTest('form: name required; AC-6 duplicate shows "Open {name}"', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.fail('POST /vendor/suppliers', 409, {
      'error': 'duplicate_supplier',
      'supplierId': _sid,
    });
    final host = await pumpPage(
      tester,
      api,
      const SupplierFormPage(),
      user: ownerUser,
      size: const Size(400, 1400),
      extraRoutes: purchaseRoutes,
    );
    await tapVisible(tester, find.byKey(const Key('supplier-form-save')));
    expect(find.text(host.tr('vendor.suppliers.nameRequired')), findsOneWidget);
    expect(api.sent('POST', '/vendor/suppliers'), isFalse);
    await typeInto(
      tester,
      find.byKey(const Key('supplier-form-name')),
      'juma supplies',
    );
    await typeInto(
      tester,
      find.byKey(const Key('supplier-form-phone')),
      '0712 345 678',
    );
    await tapVisible(tester, find.byKey(const Key('supplier-form-save')));
    final body = api.only('POST', '/vendor/suppliers').body as Map;
    expect(body, {'name': 'juma supplies', 'phone': '0712 345 678'});
    expect(
      find.text('You already have a supplier called juma supplies.'),
      findsOneWidget,
    );
    await tapVisible(
      tester,
      find.byKey(const Key('supplier-form-open-duplicate')),
    );
    expect(find.text('ROUTE-SUPPLIER $_sid'), findsOneWidget);
  });

  apiTest('form: invalid email is caught before sending', (tester, api) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    final host = await pumpPage(
      tester,
      api,
      const SupplierFormPage(),
      user: ownerUser,
      size: const Size(400, 1400),
      extraRoutes: purchaseRoutes,
    );
    await typeInto(tester, find.byKey(const Key('supplier-form-name')), 'Juma');
    await typeInto(
      tester,
      find.byKey(const Key('supplier-form-email')),
      'juma@',
    );
    await tapVisible(tester, find.byKey(const Key('supplier-form-save')));
    expect(find.text(host.tr('vendor.suppliers.invalidEmail')), findsOneWidget);
    expect(api.sent('POST', '/vendor/suppliers'), isFalse);
  });

  apiTest(
    'profile: owed, aging, open instalments, bought; archive off while owed',
    (tester, api) async {
      final semantics = tester.ensureSemantics();
      api.on('GET /vendor/tools/options', purchasesOnTools);
      api.on('GET /vendor/suppliers/$_sid', profileJson());
      api.on('GET /vendor/purchases', {
        'purchases': [
          {
            'id': 'vpo_0000000000000012',
            'number': 'GRN-000012',
            'status': 'received',
            'receivedOn': '2026-11-03',
            'supplier': {'id': _sid, 'name': 'Juma Supplies'},
            'totalTzs': 200000,
            'paidTzs': 50000,
            'balanceTzs': 150000,
            'overdueTzs': 20000,
            'paymentState': 'part_paid',
          },
        ],
        'nextCursor': null,
      });
      final host = await pumpPage(
        tester,
        api,
        const SupplierProfilePage(supplierId: _sid),
        user: ownerUser,
        size: const Size(400, 1800),
        keepRequests: true,
        extraRoutes: purchaseRoutes,
      );
      expect(
        api.requests.where((r) => r.path == '/vendor/purchases').single.query,
        contains('supplierId=$_sid'),
      );
      expect(find.text('You owe TSh 150,000'), findsOneWidget);
      expect(
        find.text("You still owe TSh 150,000, so they can't be archived."),
        findsOneWidget,
      );
      expect(
        find.text('Bought TSh 400,000 in 3 deliveries · paid TSh 250,000'),
        findsOneWidget,
      );
      expect(find.textContaining('GRN-000012 · Instalment 2'), findsOneWidget);
      expect(find.text('Receive stock from Juma Supplies'), findsOneWidget);
      expect(find.bySemanticsLabel('Call Juma Supplies'), findsOneWidget);
      await tester.tap(find.byKey(const Key('supplier-more')));
      await tester.pumpAndSettle();
      final archive = tester.widget<PopupMenuItem<String>>(
        find.byKey(const Key('supplier-archive')),
      );
      expect(archive.enabled, isFalse);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('supplier-receive')));
      expect(find.text('ROUTE-RECEIVE supplierId=$_sid'), findsOneWidget);
      expect(host.tr('vendor.suppliers.archived'), isNotEmpty);
      semantics.dispose();
    },
  );

  apiTest(
    'AC-7: archived supplier — banner, no Receive, Restore sends archived:false',
    (tester, api) async {
      api.on('GET /vendor/tools/options', purchasesOnTools);
      api.on(
        'GET /vendor/suppliers/$_sid',
        profileJson(owed: 0, archived: true),
      );
      api.on('GET /vendor/purchases', {'purchases': [], 'nextCursor': null});
      api.on('PUT /vendor/suppliers/$_sid', {
        'supplier': profileJson(owed: 0)['supplier'],
      });
      await pumpPage(
        tester,
        api,
        const SupplierProfilePage(supplierId: _sid),
        user: ownerUser,
        size: const Size(400, 1400),
        extraRoutes: purchaseRoutes,
      );
      expect(find.byKey(const Key('supplier-archived')), findsOneWidget);
      expect(find.byKey(const Key('supplier-receive')), findsNothing);
      await tester.tap(find.byKey(const Key('supplier-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('supplier-restore')));
      await tester.pumpAndSettle();
      expect(api.only('PUT', '/vendor/suppliers/$_sid').body, {
        'archived': false,
      });
    },
  );

  apiTest('409 supplier_has_balance from the server is shown in words', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.on('GET /vendor/suppliers/$_sid', profileJson(owed: 0));
    api.on('GET /vendor/purchases', {'purchases': [], 'nextCursor': null});
    api.fail('PUT /vendor/suppliers/$_sid', 409, {
      'error': 'supplier_has_balance',
      'owedTzs': 5000,
    });
    final host = await pumpPage(
      tester,
      api,
      const SupplierProfilePage(supplierId: _sid),
      user: ownerUser,
      size: const Size(400, 1400),
      extraRoutes: purchaseRoutes,
    );
    await tester.tap(find.byKey(const Key('supplier-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('supplier-archive')));
    await tester.pumpAndSettle();
    expect(
      host.snack("You still owe TSh 5,000, so they can't be archived."),
      findsOneWidget,
    );
  });
}
