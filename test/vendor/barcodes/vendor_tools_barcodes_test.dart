// Vendor tools · S8: `tools.barcodes` is on only when exactly true (fail
// closed), and every new string has English and Swahili.
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('barcodes parsed; anything but true is off', () {
    expect(VendorTools.fromOptions({'barcodes': true}).barcodes, isTrue);
    for (final v in [false, null, 'true', 1, <String, dynamic>{}]) {
      expect(
        VendorTools.fromOptions({'barcodes': v}).barcodes,
        isFalse,
        reason: '$v',
      );
    }
    expect(VendorTools.fromOptions({}).barcodes, isFalse);
    expect(VendorTools.off.barcodes, isFalse);
    expect(VendorTools.accountSuspended.barcodes, isFalse);
  });

  test('every vendor.barcodes.* / vendor.scan.* key is in EN and SW', () {
    bool s8(String k) =>
        k.startsWith('vendor.barcodes.') || k.startsWith('vendor.scan.');
    final en = FFLocale.keysOf('en').where(s8).toSet();
    final sw = FFLocale.keysOf('sw').where(s8).toSet();
    expect(en.length, greaterThanOrEqualTo(80));
    expect(sw, en);
    for (final k in en) {
      final enText = FFLocale.textOf('en', k)!;
      final swText = FFLocale.textOf('sw', k)!;
      expect(swText, isNot(enText), reason: '$k left in English');
      // Same placeholders in both languages.
      final ph = RegExp(r'\{\w+\}');
      expect(
        ph.allMatches(swText).map((m) => m[0]).toSet(),
        ph.allMatches(enText).map((m) => m[0]).toSet(),
        reason: k,
      );
    }
    expect(FFLocale.textOf('sw', 'vendor.barcodes.title'), 'Misimbopau');
    expect(
      FFLocale.textOf('sw', 'vendor.barcodes.err.inUseRetry'),
      'Msimbopau huu unatumika. Jaribu tena.',
    );
  });
}
