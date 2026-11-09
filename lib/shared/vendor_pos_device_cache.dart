// Vendor walk-in sales (S3/S8): what the POS keeps on the device for offline
// selling besides the sales themselves — the product list (with barcodes,
// S8 §7) and the receipt header. Cleared at sign-out (S8 security review
// L1) so the next person on the device does not see this vendor's
// products. The queued sales (`vendor_sale_queue.*`) and the cart draft are
// kept, so sales made offline still sync when that person signs in again.
import 'package:shared_preferences/shared_preferences.dart';

const vendorPosDeviceCachePrefixes = [
  'vendor_pos_products.',
  'vendor_pos_business.',
];

Future<void> clearVendorPosDeviceCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().toList()) {
      if (vendorPosDeviceCachePrefixes.any(k.startsWith)) await prefs.remove(k);
    }
  } catch (_) {}
}
