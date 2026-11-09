// Vendor tools · S8 §4.3: debounce, one code in flight, local index before
// the lookup, the B-11 filter, offline misses, 429 pause and resume.
import 'dart:async';

import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_controller.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _p(
  String id,
  String name, {
  String? sku,
  List? codes,
  String status = 'active',
}) => {
  'id': id,
  'name': name,
  'priceTzs': 85000,
  'stock': 10,
  'status': status,
  'sku': ?sku,
  'barcodes': ?codes,
  'costTzs': 1,
};

void main() {
  final products = [
    _p(
      'p1',
      'Whey',
      sku: 'WP-1KG',
      codes: [
        {'code': '6201234567893', 'variant': null},
      ],
    ),
    _p(
      'p2',
      'Gloves',
      codes: [
        {'code': '036000291452', 'variant': 'M'},
      ],
    ),
    _p('p3', 'Band A', sku: 'BAND'),
    _p('p4', 'Band B', sku: 'band'),
  ];

  late DateTime now;
  late List<String> looked;
  late FutureOr<List<ScanMatch>> Function(String) answer;
  VendorScanController make({bool online = true}) => VendorScanController(
    index: () => ProductCodeIndex(products),
    lookup: (code) async {
      looked.add(code);
      return answer(code);
    },
    online: () => online,
    now: () => now,
  );

  setUp(() {
    now = DateTime.utc(2026, 11, 9, 10);
    looked = [];
    answer = (_) => [];
  });

  test('local barcode match first, by codeKey (UPC-A = its EAN-13)', () async {
    final c = make();
    final o = (await c.handle('0036000291452'))!;
    expect(o.kind, ScanOutcomeKind.matched);
    expect(o.matches.single.productId, 'p2');
    expect(o.matches.single.variant, 'M');
    expect(looked, isEmpty);
  });

  test(
    'then exact SKU (any case); several SKU matches come back sorted',
    () async {
      final c = make();
      expect((await c.handle('wp-1kg'))!.matches.single.productId, 'p1');
      final band = (await c.handle('BAND'))!;
      expect(band.matches.map((m) => m.name), ['Band A', 'Band B']);
      expect(band.matches.first.matchedBy, 'sku');
      expect(looked, isEmpty);
    },
  );

  test('debounce timing', () async {
    final c = make();
    expect(await c.handle('6201234567893'), isNotNull);
    now = now.add(const Duration(milliseconds: 1499));
    expect(await c.handle('6201234567893'), isNull);
    expect(await c.handle('036000291452'), isNotNull); // a different code
    expect(await c.handle('6201234567893', typed: true), isNotNull);
    now = now.add(const Duration(milliseconds: 1600));
    expect(await c.handle('6201234567893'), isNotNull);
    c.resetDebounce();
    expect(await c.handle('6201234567893'), isNotNull);
  });

  test('no local match → lookup; the answer is kept for the session', () async {
    answer = (code) => [
      ScanMatch.fromLookup({
        'productId': 'p9',
        'name': 'New tin',
        'variant': null,
        'variants': null,
        'priceTzs': 1000,
        'discountPriceTzs': null,
        'stock': 2,
        'status': 'active',
        'approvalStatus': 'approved',
        'sku': null,
        'matchedBy': 'barcode',
      }),
    ];
    final c = make();
    final o = (await c.handle('5012345678900', typed: true))!;
    expect(o.kind, ScanOutcomeKind.matched);
    expect(o.matches.single.name, 'New tin');
    expect(looked, ['5012345678900']);
  });

  test(
    'nothing matches → notFound; offline → notFoundOffline, no lookup',
    () async {
      expect(
        (await make().handle('5012345678900'))!.kind,
        ScanOutcomeKind.notFound,
      );
      looked.clear();
      final off = make(online: false);
      expect(
        (await off.handle('5012345678900'))!.kind,
        ScanOutcomeKind.notFoundOffline,
      );
      expect(looked, isEmpty);
      // The saved list still answers offline.
      expect(
        (await off.handle('6201234567893'))!.kind,
        ScanOutcomeKind.matched,
      );
    },
  );

  test(
    'B-11: event tickets and long payloads never reach the lookup',
    () async {
      final c = make();
      expect(
        (await c.handle('FFEV1:tkt_123'))!.kind,
        ScanOutcomeKind.notProduct,
      );
      expect(
        (await c.handle('x' * 49, typed: true))!.kind,
        ScanOutcomeKind.notProduct,
      );
      expect(looked, isEmpty);
    },
  );

  test('one code in flight: others are dropped until it answers', () async {
    final gate = Completer<List<ScanMatch>>();
    answer = (_) => gate.future;
    final c = make();
    final first = c.handle('5012345678900');
    await Future<void>.delayed(Duration.zero);
    expect(c.busy, isTrue);
    expect(c.looking, '5012345678900');
    expect(await c.handle('6201234567893', typed: true), isNull);
    gate.complete([]);
    expect((await first)!.kind, ScanOutcomeKind.notFound);
    expect(c.busy, isFalse);
    // A held scanner (a sheet is open) drops codes too.
    c.hold();
    expect(c.held, isTrue);
    expect(await c.handle('6201234567893', typed: true), isNull);
    c.release();
    expect(await c.handle('6201234567893', typed: true), isNotNull);
  });

  test(
    '429: rateLimited with seconds; camera codes wait, then it resumes',
    () async {
      answer = (_) => throw ApiException(429, {
        'error': 'rate_limited',
        'retryAfterSeconds': 7,
      });
      final c = make();
      final o = (await c.handle('5012345678900', typed: true))!;
      expect(o.kind, ScanOutcomeKind.rateLimited);
      expect(o.seconds, 7);
      expect(c.rateLimited, isTrue);
      looked.clear();
      expect(await c.handle('5012345678901'), isNull);
      expect(
        (await c.handle('5012345678901', typed: true))!.kind,
        ScanOutcomeKind.rateLimited,
      );
      expect(looked, isEmpty);
      now = now.add(const Duration(seconds: 8));
      answer = (_) => [];
      expect(
        (await c.handle('5012345678901', typed: true))!.kind,
        ScanOutcomeKind.notFound,
      );
      c.dispose();
    },
  );

  test(
    'refusals: 404 feature_disabled, 403, vendor_suspended, network',
    () async {
      Future<ScanOutcomeKind> kindFor(Object error) async {
        answer = (_) => throw error;
        return (await make().handle('5012345678900', typed: true))!.kind;
      }

      expect(
        await kindFor(ApiException(404, {'error': 'feature_disabled'})),
        ScanOutcomeKind.featureOff,
      );
      expect(
        await kindFor(
          ApiException(403, {'error': 'vendor_permission_forbidden'}),
        ),
        ScanOutcomeKind.noAccess,
      );
      expect(
        await kindFor(ApiException(403, {'error': 'vendor_suspended'})),
        ScanOutcomeKind.suspended,
      );
      expect(
        await kindFor(ApiException(400, {'error': 'invalid_code'})),
        ScanOutcomeKind.notFound,
      );
      expect(
        await kindFor(ApiException(503, {'error': 'x'})),
        ScanOutcomeKind.lookupFailed,
      );
      expect(await kindFor(Exception('offline')), ScanOutcomeKind.lookupFailed);
    },
  );

  test('a lookup match with a variant carries that variant\'s stock', () {
    final m = ScanMatch.fromLookup({
      'productId': 'p2',
      'name': 'Gloves',
      'variant': 'M',
      'variants': null,
      'priceTzs': 1,
      'stock': 4,
      'status': 'active',
      'approvalStatus': 'approved',
      'matchedBy': 'barcode',
    });
    expect(m.asProduct['variants'], [
      {'name': 'M', 'stock': 4},
    ]);
    expect(m.label, 'Gloves (M)');
  });
}
