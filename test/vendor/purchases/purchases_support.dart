// Shared seeds for the vendor purchases tests (vendor tools · S9, backend
// fitflex-functions#327). Nothing here talks to a real server: every answer
// comes from the RecordingApi fake at http://fixtures.local.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../support/recording_api.dart';

const purchasesOnTools = {
  'stockLedger': true,
  'canSeeCost': true,
  'purchases': true,
};
const purchasesOnNoCost = {
  'stockLedger': true,
  'canSeeCost': false,
  'purchases': true,
};
const purchasesOffTools = {
  'stockLedger': true,
  'canSeeCost': true,
  'purchases': false,
};

const ownerUser = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Owner'};

Map<String, dynamic> staffUser(
  List<String> perms, {
  String role = 'inventory_manager',
  String id = 's1',
}) => {
  'id': id,
  'userType': 'vendor_staff',
  'vendorId': 'v1',
  'vendorRole': role,
  'displayName': 'Asha',
  'vendorPermissions': perms,
};

/// The plain product (cost TSh 9,000, stock 3) and one with tracked
/// variants (S / M / L).
List<Map<String, dynamic>> purchaseProducts() => [
  {
    'id': 'p1',
    'name': 'Whey 1kg',
    'sku': 'WH1',
    'priceTzs': 15000,
    'stock': 3,
    'status': 'active',
    'approvalStatus': 'approved',
    'variants': [],
    'costTzs': 9000,
  },
  {
    'id': 'p2',
    'name': 'Tee',
    'priceTzs': 20000,
    'stock': 9,
    'status': 'paused',
    'approvalStatus': 'approved',
    'variants': [
      {'name': 'S', 'stock': 3, 'costTzs': null, 'effectiveCostTzs': 5000},
      {'name': 'M', 'stock': 3, 'costTzs': 6000, 'effectiveCostTzs': 6000},
      {'name': 'L', 'stock': 3, 'costTzs': null, 'effectiveCostTzs': 5000},
    ],
    'costTzs': 5000,
  },
  {
    'id': 'p3',
    'name': 'Old mat',
    'priceTzs': 1000,
    'stock': 0,
    'status': 'archived',
    'variants': [],
  },
];

/// A purchase as GET /vendor/purchases/:id sends it. Defaults: GRN-000012,
/// Juma Supplies, 200,000 total, 50,000 paid at delivery (M-Pesa), 3
/// monthly instalments of 50,000 after it.
Map<String, dynamic> purchaseJson({
  String id = 'vpo_0000000000000012',
  String status = 'received',
  int total = 200000,
  int paid = 50000,
  int overdue = 0,
  String createdById = 'v1',
  String recordedAt = '2026-11-03T07:05:00.000Z',
  String receivedOn = '2026-11-03',
  List<Map<String, dynamic>>? instalments,
  List<Map<String, dynamic>>? payments,
  bool withSupplier = true,
  bool costUpdated = true,
  int? previousCost = 9000,
  bool? costRestored,
}) {
  final balance = total - paid;
  return {
    'id': id,
    'number': 'GRN-000012',
    'status': status,
    'supplier': withSupplier
        ? {
            'id': 'vsp_0000000000000001',
            'name': 'Juma Supplies',
            'archived': false,
          }
        : null,
    'receivedOn': receivedOn,
    'recordedAt': recordedAt,
    'supplierInvoiceRef': 'INV-4471',
    'note': 'Back door, Mr Ali',
    'createdBy': {'id': createdById, 'name': 'Asha'},
    'totalTzs': total,
    'paidTzs': paid,
    'balanceTzs': balance,
    'overdueTzs': overdue,
    'paymentState': balance == 0
        ? 'paid'
        : paid > 0
        ? 'part_paid'
        : 'unpaid',
    'nextDue': balance == 0
        ? null
        : {'dueDate': '2026-12-03', 'openTzs': 50000, 'daysOverdue': 0},
    'lines': [
      {
        'id': 'vpl_1',
        'productId': 'p1',
        'variant': null,
        'nameSnapshot': 'Whey 1kg',
        'qty': 20,
        'unitCostTzs': 9500,
        'lineTotalTzs': 190000,
        'costUpdated': costUpdated,
        'free': false,
        'previousCostTzs': ?previousCost,
        'costRestoredOnVoid': costRestored,
      },
      {
        'id': 'vpl_2',
        'productId': 'p2',
        'variant': 'M',
        'nameSnapshot': 'Tee',
        'qty': 1,
        'unitCostTzs': 10000,
        'lineTotalTzs': 10000,
        'costUpdated': false,
        'free': false,
        'costRestoredOnVoid': null,
      },
    ],
    'instalments':
        instalments ??
        [
          inst(1, '2026-11-03', 50000, 50000, 'paid'),
          inst(2, '2026-12-03', 50000, 0, 'due'),
          inst(3, '2027-01-03', 50000, 0, 'due'),
          inst(4, '2027-02-03', 50000, 0, 'due'),
        ],
    'payments': payments ?? [paymentJson()],
    'voidedBy': status == 'voided' ? {'id': 'v1', 'name': 'Owner'} : null,
    'voidedAt': status == 'voided' ? '2026-11-03T09:00:00.000Z' : null,
    'voidReason': status == 'voided' ? 'Wrong delivery' : null,
  };
}

Map<String, dynamic> inst(
  int seq,
  String due,
  int amount,
  int covered,
  String state, {
  int daysOverdue = 0,
}) => {
  'id': 'vpi_$seq',
  'seq': seq,
  'dueDate': due,
  'amountTzs': amount,
  'coveredTzs': covered,
  'openTzs': amount - covered,
  'state': state,
  'daysOverdue': daysOverdue,
};

Map<String, dynamic> paymentJson({
  String id = 'vpp_1',
  int amount = 50000,
  String status = 'recorded',
  String recordedById = 'v1',
  String recordedAt = '2026-11-03T07:05:00.000Z',
  bool atReceipt = true,
}) => {
  'id': id,
  'amountTzs': amount,
  'paidOn': '2026-11-03',
  'method': 'mpesa',
  'reference': 'QK12AB34',
  'note': null,
  'atReceipt': atReceipt,
  'recordedBy': {'id': recordedById, 'name': 'Asha'},
  'recordedAt': recordedAt,
  'status': status,
  'voidedBy': status == 'voided' ? {'id': 'v1', 'name': 'Owner'} : null,
  'voidedAt': status == 'voided' ? '2026-11-03T10:00:00.000Z' : null,
  'voidReason': status == 'voided' ? 'Recorded twice' : null,
  'voidedWithPurchase': false,
};

Map<String, dynamic> supplierRow(
  String id,
  String name, {
  int owed = 0,
  int overdue = 0,
  String? phone = '+255712345678',
  bool archived = false,
}) => {
  'id': id,
  'name': name,
  'phone': phone,
  'contactPerson': null,
  'owedTzs': owed,
  'overdueTzs': overdue,
  'nextDueDate': owed > 0 ? '2026-12-03' : null,
  'lastReceivedOn': '2026-11-03',
  'archived': archived,
};

Map<String, dynamic> agingJson({int owed = 150000, int overdue = 20000}) => {
  'asOf': '2026-11-03',
  'totals': {
    'owedTzs': owed,
    'overdueTzs': overdue,
    'supplierCount': owed > 0 ? 1 : 0,
    'overdueSupplierCount': overdue > 0 ? 1 : 0,
    'dueIn7DaysTzs': 30000,
    'current': owed - overdue,
    'd1_30': overdue,
    'd31_60': 0,
    'd61_90': 0,
    'd90plus': 0,
  },
  'rows': owed == 0
      ? []
      : [
          {
            'supplierId': 'vsp_0000000000000001',
            'name': 'Juma Supplies',
            'owedTzs': owed,
            'overdueTzs': overdue,
            'oldestDueDate': '2026-10-20',
            'maxDaysOverdue': overdue > 0 ? 14 : 0,
            'current': owed - overdue,
            'd1_30': overdue,
            'd31_60': 0,
            'd61_90': 0,
            'd90plus': 0,
          },
        ],
  'nextCursor': null,
};

/// Pages the purchase screens move to, shown as markers.
final purchaseRoutes = <RouteBase>[
  GoRoute(
    path: '/vendor/home',
    builder: (_, s) => Scaffold(body: Text('ROUTE-VENDOR-HOME ${s.uri.query}')),
  ),
  GoRoute(
    path: '/vendor/purchases/receive',
    builder: (_, s) => Scaffold(body: Text('ROUTE-RECEIVE ${s.uri.query}')),
  ),
  GoRoute(
    path: '/vendor/purchases/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-PURCHASE ${s.pathParameters['id']}')),
  ),
  GoRoute(
    path: '/vendor/suppliers/new',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-SUPPLIER-NEW')),
  ),
  GoRoute(
    path: '/vendor/suppliers/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-SUPPLIER ${s.pathParameters['id']}')),
    routes: [
      GoRoute(
        path: 'edit',
        builder: (_, s) => Scaffold(
          body: Text('ROUTE-SUPPLIER-EDIT ${s.pathParameters['id']}'),
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/vendor/suppliers',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-SUPPLIERS')),
  ),
  GoRoute(
    path: '/vendor/payables',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-PAYABLES')),
  ),
  GoRoute(
    path: '/vendor/products/:id/stock',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-STOCK ${s.pathParameters['id']}')),
  ),
];

/// Seeds what the receive screen reads.
void seedReceive(
  RecordingApi api, {
  Map<String, dynamic> tools = purchasesOnTools,
  List<Map<String, dynamic>>? lastCosts,
}) {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/products', purchaseProducts());
  api.on('GET /vendor/purchases/last-costs', {'rows': lastCosts ?? []});
  api.on('GET /vendor/suppliers', {
    'suppliers': [
      supplierRow('vsp_0000000000000001', 'Juma Supplies', owed: 40000),
      supplierRow('vsp_0000000000000002', 'Kariakoo Traders'),
    ],
    'nextCursor': null,
  });
}
