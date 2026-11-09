// Labels for account and conversation statuses the server sends as codes
// ("pending_verification", "resolved"): a code is never shown raw. Each has
// a label in both languages, and one the app does not know yet falls back to
// readable text.
//
// Use the dedicated helpers first where they exist: shop orders
// (`shopOrderStatusLabel`), shop payments (`shopPaymentStatusLabel`,
// `shopPaymentMethodLabel`), gym tiers (`tierLabel` / `gymTierLabel`) and
// pass access (`passGymAccessLabel`).

import 'package:flutter/widgets.dart';

import 'i18n.dart';

String _code(String? value) =>
    (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

/// "pending_verification" → "Pending verification".
String _readable(String value) {
  final clean = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (clean.isEmpty) return '';
  return '${clean[0].toUpperCase()}${clean.substring(1)}';
}

/// A gym, vendor-account or enquiry status in the app's language, or
/// [fallback] when there is none.
String statusLabel(
  BuildContext context,
  String? status, {
  String fallback = '',
}) {
  final code = switch (_code(status)) {
    'canceled' => 'cancelled',
    final other => other,
  };
  if (code.isEmpty) return fallback;
  final key = 'wire.status.$code';
  final label = context.tr(key);
  return label == key ? _readable(status!) : label;
}
