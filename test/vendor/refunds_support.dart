// Shared seeds for the vendor refund tests (vendor tools · S7, backend
// fitflex-functions#318). Nothing here talks to a real server.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const refundsOn = {
  'walkInSales': true,
  'stockLedger': true,
  'canSeeCost': true,
  'refunds': true,
};
const refundsOff = {
  'walkInSales': true,
  'stockLedger': true,
  'canSeeCost': true,
  'refunds': false,
};

const ownerUser = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Owner'};

/// A cash sale: 3 × Whey (TSh 3,500, TSh 500 line discount → net 10,000)
/// and 1 × Mat (TSh 10,000). The AC-6 seed.
Map<String, dynamic> refundSale({
  String id = 'sal_1',
  String status = 'completed',
  String kind = 'cash',
  int balanceTzs = 0,
  int wheyRefunded = 0,
  int wheyRefundedTzs = 0,
  int matRefunded = 0,
  String createdById = 'v1',
  String soldAt = '2026-11-03T08:00:00.000Z',
  List<Map<String, dynamic>> refunds = const [],
  List<Map<String, dynamic>>? payments,
}) {
  final matRefundedTzs = matRefunded * 10000;
  final refunded = wheyRefundedTzs + matRefundedTzs;
  final full = wheyRefunded == 3 && matRefunded == 1;
  return {
    'id': id,
    'number': 'R-000123',
    'status': status,
    'kind': kind,
    'soldAt': soldAt,
    'recordedAt': soldAt,
    'clientRef': 'sale_x_00000001',
    'subtotalTzs': 20500,
    'lineDiscountTzs': 500,
    'discountTzs': 0,
    'totalTzs': 20000,
    'paidTzs': kind == 'credit' ? 20000 - balanceTzs : 20000,
    'changeTzs': 0,
    'balanceTzs': balanceTzs,
    if (kind == 'credit')
      'customer': {'id': 'cus_1', 'name': 'Neema', 'forgotten': false},
    'createdBy': {'id': createdById, 'name': 'Asha'},
    'voidedBy': null,
    'voidedAt': status == 'voided' ? soldAt : null,
    'voidReason': status == 'voided' ? 'Mistake' : null,
    'refundedTzs': refunded,
    'refundableTzs': 20000 - refunded,
    'netAfterRefundsTzs': 20000 - refunded,
    'refundState': refunded == 0
        ? 'none'
        : full
        ? 'full'
        : 'partial',
    'balanceReducedTzs': 0,
    'refunds': refunds,
    'lines': [
      {
        'id': 'sln_a',
        'productId': 'p1',
        'variant': null,
        'nameSnapshot': 'Whey',
        'qty': 3,
        'listPriceTzs': 3500,
        'unitPriceTzs': 3500,
        'priceChanged': false,
        'discountTzs': 500,
        'lineTotalTzs': 10000,
        'lineNetTzs': 10000,
        'refundedQty': wheyRefunded,
        'refundableQty': 3 - wheyRefunded,
        'refundedTzs': wheyRefundedTzs,
      },
      {
        'id': 'sln_b',
        'productId': 'p2',
        'variant': null,
        'nameSnapshot': 'Mat',
        'qty': 1,
        'listPriceTzs': 10000,
        'unitPriceTzs': 10000,
        'priceChanged': false,
        'discountTzs': 0,
        'lineTotalTzs': 10000,
        'lineNetTzs': 10000,
        'refundedQty': matRefunded,
        'refundableQty': 1 - matRefunded,
        'refundedTzs': matRefundedTzs,
      },
    ],
    'payments':
        payments ??
        (kind == 'credit'
            ? const []
            : [
                {'method': 'mpesa', 'amountTzs': 20000, 'reference': 'QX1'},
              ]),
  };
}

Map<String, dynamic> refundJson({
  String id = 'vrf_0000000000000001',
  String number = 'CN-000004',
  String status = 'active',
  String createdById = 'v1',
  String refundedAt = '2026-11-03T11:05:00.000Z',
  String kind = 'cash',
  int amount = 3333,
  int balanceReduced = 0,
  String? method = 'cash',
  String? reference,
  bool restock = true,
}) => {
  'id': id,
  'number': number,
  'status': status,
  'saleId': 'sal_1',
  'saleNumber': 'R-000123',
  'saleInvoiceNumber': kind == 'credit' ? 'INV-000045' : null,
  'saleKind': kind,
  'refundedAt': refundedAt,
  'createdBy': {'id': createdById, 'name': 'Asha'},
  'reason': 'Customer returned it',
  'method': amount - balanceReduced > 0 ? method : null,
  'reference': reference,
  'amountTzs': amount,
  'balanceReducedTzs': balanceReduced,
  'paidOutTzs': amount - balanceReduced,
  'vatTzs': 0,
  'vatSummary': const [],
  'customer': kind == 'credit'
      ? {'id': 'cus_1', 'name': 'Neema', 'forgotten': false}
      : null,
  'lines': [
    {
      'saleLineId': 'sln_a',
      'productId': 'p1',
      'variant': null,
      'nameSnapshot': 'Whey',
      'qty': 1,
      'unitPriceTzs': 3500,
      'amountTzs': amount,
      'vatTzs': 0,
      'vatCode': null,
      'restock': restock,
    },
  ],
  'revertedBy': status == 'reverted' ? {'id': 'v1', 'name': 'Owner'} : null,
  'revertedAt': status == 'reverted' ? '2026-11-03T12:00:00.000Z' : null,
  'revertReason': status == 'reverted' ? 'Wrong sale' : null,
};

/// Pages the refund screens move to, shown as markers.
final refundRoutes = <RouteBase>[
  GoRoute(
    path: '/vendor/home',
    builder: (_, s) => Scaffold(body: Text('ROUTE-VENDOR-HOME ${s.uri.query}')),
  ),
  GoRoute(
    path: '/vendor/sales/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-SALE ${s.pathParameters['id']}')),
    routes: [
      GoRoute(
        path: 'refund',
        builder: (_, s) =>
            Scaffold(body: Text('ROUTE-REFUND ${s.pathParameters['id']}')),
      ),
    ],
  ),
  GoRoute(
    path: '/vendor/refunds/:id',
    builder: (_, s) => Scaffold(
      body: Text(
        'ROUTE-REFUND-DETAIL ${s.pathParameters['id']} ${s.uri.query}',
      ),
    ),
  ),
  GoRoute(
    path: '/vendor/products/:id/stock',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-STOCK ${s.pathParameters['id']}')),
  ),
];
