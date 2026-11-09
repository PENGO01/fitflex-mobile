// Flutter web only: where mobile_scanner loads its barcode library from
// (vendor tools S8, Q-3, owner decision 2026-11-09).
//
// mobile_scanner 6.0.11 on the web reads codes with ZXing, which it loads
// at run time from https://unpkg.com/@zxing/library@0.21.3 unless told
// otherwise. The app ships a pinned copy instead, served from its own
// origin, so the web app runs no third-party CDN code and the camera still
// works where unpkg is blocked. This covers every scan page on the web: the
// member gym check-in scan, the owner QR scanner and the vendor scan panel.
//
// The file (web/vendor/zxing-library-0.21.3/index.min.js) is the `umd/
// index.min.js` of the npm package @zxing/library 0.21.3, byte for byte:
//   source  https://registry.npmjs.org/@zxing/library/-/library-0.21.3.tgz
//           (npm integrity sha512-hZHqFe2JyH/ZxviJZosZjV+2s6EDSY0O24R+FQmlWZBZXP9IqMo7S3nb3+2LBWxodJQkSurdQGnqE7KXqrYgow==),
//           identical to https://unpkg.com/@zxing/library@0.21.3/umd/index.min.js
//   sha256  d7cc8f69dd70bdcf3ac00c9ae572bf2acb9f4132ba379c72df842e4db918652d
// Its LICENSE from the same package sits beside it. Upgrading mobile_scanner
// means checking which ZXing version it expects and replacing both.
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The pinned ZXing build, relative to the page's `<base href>`.
const zxingLibraryPath = 'vendor/zxing-library-0.21.3/index.min.js';

/// The version the pinned file is (mobile_scanner 6.0.11 expects 0.21.3).
const zxingLibraryVersion = '0.21.3';

/// The sha256 of the pinned file (checked by a test).
const zxingLibrarySha256 =
    'd7cc8f69dd70bdcf3ac00c9ae572bf2acb9f4132ba379c72df842e4db918652d';

/// Points mobile_scanner at the pinned copy. Call once at start-up, before
/// any camera starts. Does nothing off the web.
void useBundledBarcodeLibrary() {
  if (!kIsWeb) return;
  MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(zxingLibraryPath);
}
