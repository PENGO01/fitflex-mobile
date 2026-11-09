// Vendor tools · S8 (barcodes): the code rules, the same as the server
// (fitflex-functions src/shared/vendor-barcode.mjs) and the portal. The
// shared test vectors are test/fixtures/barcode-vectors.json.
//
// B-1 a code is 4–48 printable ASCII characters (0x21–0x7E) after trimming.
// B-2 codeKey: all digits, 12 long (UPC-A) → '0' + code; all digits, 14 long
//     starting with 0 → drop that 0; other all-digit codes unchanged (8
//     digits are never expanded); anything else → upper case.
// B-3 all-digit codes 12, 13 or 14 long must pass the GTIN mod-10 check.
// B-5 at most 20 codes per product.
// B-11 a FitFlex QR (event ticket) or anything over 48 characters is not a
//     product code and is never looked up.
import '../../../shared/events/event_ticket.dart';

const barcodeMinLength = 4;
const barcodeMaxLength = 48;
const maxBarcodesPerProduct = 20;
const lookupCodeMaxLength = 100;

final _printable = RegExp(r'^[\x21-\x7E]+$');
final _digits = RegExp(r'^\d+$');

/// GTIN mod-10 check (EAN-8/12/13/14): weights 3, 1, 3, … from the digit
/// left of the check digit.
bool checkGtin(String digits) {
  if (!_digits.hasMatch(digits) || digits.length < 2) return false;
  var sum = 0;
  var w = 3;
  for (var i = digits.length - 2; i >= 0; i--) {
    sum += (digits.codeUnitAt(i) - 48) * w;
    w = w == 3 ? 1 : 3;
  }
  return (10 - (sum % 10)) % 10 == digits.codeUnitAt(digits.length - 1) - 48;
}

/// B-2: the key codes are compared by. Never throws; the input is trimmed.
String codeKey(String? raw) {
  final code = (raw ?? '').trim();
  if (_digits.hasMatch(code)) {
    if (code.length == 12) return '0$code';
    if (code.length == 14 && code.startsWith('0')) return code.substring(1);
    return code;
  }
  return code.toUpperCase();
}

/// The result of checking one code (B-1, B-3).
class BarcodeCheck {
  const BarcodeCheck._({required this.code, this.key, this.error, this.reason});

  /// The code as entered, trimmed.
  final String code;

  /// The matching key; null when the code is not valid.
  final String? key;

  /// `invalid_barcode` or `invalid_check_digit` (the server's error codes).
  final String? error;

  /// For `invalid_barcode`: `too_short`, `too_long` or `bad_characters`.
  final String? reason;

  bool get ok => error == null;
}

/// B-1 + B-3 on one code.
BarcodeCheck validateBarcode(String? raw) {
  final code = (raw ?? '').trim();
  BarcodeCheck bad(String reason) =>
      BarcodeCheck._(code: code, error: 'invalid_barcode', reason: reason);
  if (code.length < barcodeMinLength) return bad('too_short');
  if (code.length > barcodeMaxLength) return bad('too_long');
  if (!_printable.hasMatch(code)) return bad('bad_characters');
  if (_digits.hasMatch(code) &&
      const {12, 13, 14}.contains(code.length) &&
      !checkGtin(code)) {
    return BarcodeCheck._(code: code, error: 'invalid_check_digit');
  }
  return BarcodeCheck._(code: code, key: codeKey(code));
}

/// Text typed in a search field that may be a code (§5.1): no spaces,
/// 4–48 printable characters.
bool looksLikeCode(String text) {
  final t = text.trim();
  return t.length >= barcodeMinLength &&
      t.length <= barcodeMaxLength &&
      _printable.hasMatch(t);
}

/// B-11: a FitFlex event ticket, a member check-in token or a URL (longer
/// than 48) is not a product code.
bool isNotProductCode(String raw) {
  final t = raw.trim();
  return isEventTicketPayload(t) || t.length > barcodeMaxLength;
}

/// The i18n key for a code problem (client check or server error).
String barcodeErrorKey(String? error, {String? reason}) =>
    switch ((error, reason)) {
      ('invalid_barcode', 'too_long') => 'vendor.barcodes.err.tooLong',
      ('invalid_barcode', 'bad_characters') => 'vendor.barcodes.err.badChars',
      ('invalid_barcode', _) => 'vendor.barcodes.err.tooShort',
      ('invalid_check_digit', _) => 'vendor.barcodes.err.checkDigit',
      ('duplicate_barcode', _) => 'vendor.barcodes.err.duplicate',
      ('barcode_in_use', _) => 'vendor.barcodes.err.inUse',
      ('too_many_barcodes', _) => 'vendor.barcodes.err.tooMany',
      ('barcode_variant_not_found', _) => 'vendor.barcodes.err.variantGone',
      _ => 'vendor.saveFailed',
    };

/// 409 `barcode_in_use`: "Already on {name}", or — when the server could
/// not name the product (`name` null: a save retried after a database
/// deadlock that failed twice) — "This code is in use. Try again."
String barcodeInUseKey(Object? body) {
  final name = body is Map ? body['name'] : null;
  return name is String && name.trim().isNotEmpty
      ? 'vendor.barcodes.err.inUse'
      : 'vendor.barcodes.err.inUseRetry';
}

/// One stored code: `variant` null = the whole product.
typedef ProductBarcode = ({String code, String? variant});

/// The codes of a vendor product map (`barcodes: [{code, variant|null}]`).
/// Absent (flag off) or malformed: none.
List<ProductBarcode> barcodesOf(Map<String, dynamic>? product) => [
  for (final b in (product?['barcodes'] as List? ?? const []).whereType<Map>())
    if (b['code'] is String && (b['code'] as String).trim().isNotEmpty)
      (
        code: (b['code'] as String).trim(),
        variant: b['variant'] is String && (b['variant'] as String).isNotEmpty
            ? b['variant'] as String
            : null,
      ),
];

/// A code's digits read one by one ("6 2 0 1 …") for screen readers.
String spokenCode(String code) => code.split('').join(' ');
