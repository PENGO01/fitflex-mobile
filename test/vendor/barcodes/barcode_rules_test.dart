// Vendor tools · S8: the app's code rules match the server's exactly, vector
// by vector (test/fixtures/barcode-vectors.json is a byte-for-byte copy of
// fitflex-functions specs/fixtures/barcode-vectors.json, functions#334).
import 'dart:convert';
import 'dart:io';

import 'package:fitflexmobile/screens/vendor/barcodes/barcode_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/sha256.dart';

/// sha256 of the backend copy at functions#334 (c8ec132). A change on
/// either side shows here first: copy the file again and re-run.
const _backendVectorsSha256 =
    'adba33aba6e5852dcafbd20a567b43f2be9f98258dc7094f5a0f8e977c52ffb5';

void main() {
  final file = File('test/fixtures/barcode-vectors.json');
  final data = jsonDecode(file.readAsStringSync()) as Map;
  final vectors = (data['vectors'] as List).cast<Map>();

  test('the vectors file is the backend copy (version 1)', () {
    expect(sha256Hex(file.readAsBytesSync()), _backendVectorsSha256);
    expect(data['version'], 1);
    expect(vectors, hasLength(23));
  });

  for (final v in vectors) {
    final input = v['input'] as String;
    test('vector ${jsonEncode(input)} → ${v['codeKey'] ?? v['error']}', () {
      final check = validateBarcode(input);
      if (v.containsKey('codeKey')) {
        expect(check.ok, isTrue, reason: '${check.error} ${check.reason}');
        expect(check.key, v['codeKey']);
        expect(codeKey(input), v['codeKey']);
      } else {
        expect(check.ok, isFalse);
        expect(check.error, v['error']);
        if (v['reason'] != null) expect(check.reason, v['reason']);
      }
    });
  }

  test('GTIN check digit', () {
    expect(checkGtin('6201234567893'), isTrue);
    expect(checkGtin('6201234567891'), isFalse);
    expect(checkGtin('036000291452'), isTrue);
    expect(checkGtin('00036000291452'), isTrue);
    expect(checkGtin('96385074'), isTrue); // EAN-8
    expect(checkGtin('12a4'), isFalse);
  });

  test('UPC-A, EAN-13 and GTIN-14 of one item share a key (AC-8)', () {
    expect(codeKey('036000291452'), codeKey('0036000291452'));
    expect(codeKey('00036000291452'), codeKey('036000291452'));
    expect(codeKey('abc-123'), codeKey('ABC-123'));
  });

  test('B-11: event tickets and long payloads are not product codes', () {
    expect(isNotProductCode('FFEV1:abc'), isTrue);
    expect(
      isNotProductCode('https://fitflex.africa/m/check-in/xyz-123456789012345'),
      isTrue,
    );
    expect(isNotProductCode('6201234567893'), isFalse);
  });

  test('looksLikeCode: no spaces, 4–48 printable', () {
    expect(looksLikeCode('6201234567893'), isTrue);
    expect(looksLikeCode('WP-1KG'), isTrue);
    expect(looksLikeCode('whey protein'), isFalse);
    expect(looksLikeCode('abc'), isFalse);
  });

  test('error keys, and 409 with no product named', () {
    expect(
      barcodeErrorKey('invalid_barcode', reason: 'too_long'),
      'vendor.barcodes.err.tooLong',
    );
    expect(
      barcodeErrorKey('invalid_check_digit'),
      'vendor.barcodes.err.checkDigit',
    );
    expect(barcodeInUseKey({'name': 'Whey'}), 'vendor.barcodes.err.inUse');
    expect(
      barcodeInUseKey({'name': null, 'productId': null}),
      'vendor.barcodes.err.inUseRetry',
    );
  });

  test('barcodesOf reads [{code, variant|null}] and ignores junk', () {
    expect(
      barcodesOf({
        'barcodes': [
          {'code': '6201234567893', 'variant': null},
          {'code': 'ABC-1', 'variant': 'M'},
          {'code': 5},
          'x',
        ],
      }),
      [(code: '6201234567893', variant: null), (code: 'ABC-1', variant: 'M')],
    );
    expect(barcodesOf({'name': 'no key (flag off)'}), isEmpty);
  });

  test('L5: check-in tokens and fitflex:gym: codes are not product codes', () {
    expect(isNotProductCode('usr_1.29512345.AbCdEfGhIjKl_-12'), isTrue);
    expect(isNotProductCode('fitflex:gym:gym_1:sig'), isTrue);
    // A real Code 128 with dots is still a product code.
    expect(isNotProductCode('AB.12.CD'), isFalse);
  });
}
