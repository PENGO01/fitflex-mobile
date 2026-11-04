// Vendor tools · S9 (spec §4.9, Q-5): the unfinished Receive stock form,
// kept on this device so typed lines are not lost. One draft per vendor and
// person. It holds unit costs, so it is removed on sign-out. It never holds
// a clientRef that was sent: a delivery is never queued.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class VendorPurchaseDraftStore {
  VendorPurchaseDraftStore._();

  static const prefix = 'vendor_purchase_draft.';

  /// The key for this vendor + person, or null when it cannot be told.
  static String? keyFor(Map<String, dynamic>? user) {
    final type = user?['userType']?.toString();
    final id = user?['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final vendor = type == 'vendor_staff'
        ? (user?['vendorId']?.toString() ?? '')
        : type == 'vendor'
        ? id
        : '';
    if (vendor.isEmpty) return null;
    return '$prefix$vendor.$id';
  }

  static Future<Map<String, dynamic>?> load(String? key) async {
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? key, Map<String, dynamic> draft) async {
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(draft));
    } catch (_) {
      // Not kept; the form on screen still has it.
    }
  }

  static Future<void> clear(String? key) async {
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  /// Sign-out: every kept delivery draft on this device goes (cost figures).
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(prefix))) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
