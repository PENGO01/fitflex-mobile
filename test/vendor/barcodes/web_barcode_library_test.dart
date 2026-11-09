// Vendor tools · S8 Q-3: Flutter web loads ZXing from the app's own origin
// (a pinned copy under web/), not from unpkg at run time. This covers the
// member, owner and vendor scan pages alike.
import 'dart:io';

import 'package:fitflexmobile/shared/barcode_library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/sha256.dart';

void main() {
  test('the pinned file is @zxing/library 0.21.3 umd/index.min.js', () {
    final file = File('web/$zxingLibraryPath');
    expect(file.existsSync(), isTrue);
    expect(sha256Hex(file.readAsBytesSync()), zxingLibrarySha256);
    expect(
      zxingLibrarySha256,
      'd7cc8f69dd70bdcf3ac00c9ae572bf2acb9f4132ba379c72df842e4db918652d',
    );
    expect(zxingLibraryVersion, '0.21.3');
    expect(
      File('web/vendor/zxing-library-0.21.3/LICENSE').existsSync(),
      isTrue,
    );
  });

  test('the path is relative to <base href>, not a CDN', () {
    expect(zxingLibraryPath.startsWith('http'), isFalse);
    expect(zxingLibraryPath.startsWith('/'), isFalse);
    expect(File('web/index.html').readAsStringSync(), isNot(contains('unpkg')));
  });

  test('main() points mobile_scanner at it before anything else runs', () {
    final main = File('lib/main.dart').readAsStringSync();
    final setup = main.indexOf('useBundledBarcodeLibrary();');
    expect(setup, greaterThan(0));
    expect(
      setup,
      greaterThan(main.indexOf('WidgetsFlutterBinding.ensureInitialized();')),
    );
    expect(setup, lessThan(main.indexOf('runApp(')));
  });

  test('off the web it does nothing (no throw)', () {
    useBundledBarcodeLibrary();
  });
}
