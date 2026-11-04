// Vendor smart import V3: what a refusal says. The server sends
// `{error, message: {en, sw}, reasonMessage?}`; that text is shown as given,
// in the active language. When there is none (an HTML error page, a proxy),
// the app's own wording for the code is used. A raw code ("duplicate_file")
// is never shown to anyone.
import '../../../shared/api_client.dart';
import 'import_models.dart';

/// The server's machine-readable code, e.g. `duplicate_file`.
String? importErrorCode(Object? error) =>
    error is ApiException ? error.code : null;

Map<String, dynamic> _body(Object? error) => error is ApiException
    ? (error.body is Map
          ? Map<String, dynamic>.from(error.body as Map)
          : <String, dynamic>{})
    : const {};

/// Extra fields of the answer, e.g. `batchId` of a `duplicate_file`.
T? importErrorField<T>(Object? error, String key) {
  final v = _body(error)[key];
  return v is T ? v : null;
}

/// `{waitSeconds}` the server asked for (`retryAfterSeconds`), if any.
int? importRetryAfterSeconds(Object? error) {
  final v = _body(error)['retryAfterSeconds'];
  return v is num && v > 0 ? v.toInt() : null;
}

/// The id of the batch that already holds the same file, for a
/// `duplicate_file` refusal.
String? importDuplicateBatchId(Object? error) =>
    importErrorCode(error) == 'duplicate_file'
    ? importErrorField<String>(error, 'batchId')
    : null;

/// The app's own wording (an i18n key) for [code], when it has some. Codes
/// without a key fall to the status-based lines.
const _keyForCode = {
  'rate_limited': 'vendor.import.err.rateLimited',
  'file_too_large': 'vendor.import.err.tooLarge',
  'too_many_rows': 'vendor.import.err.tooManyRows',
  'unsupported_file_type': 'vendor.import.err.unsupportedType',
  'invalid_encoding': 'vendor.import.err.encoding',
  'duplicate_file': 'vendor.import.err.duplicate',
  'apply_in_progress': 'vendor.import.err.busy',
  'import_busy': 'vendor.import.err.busy',
  'request_aborted': 'vendor.import.err.aborted',
  'batch_expired': 'vendor.import.err.expired',
  'import_not_found': 'vendor.import.err.notFound',
  'batch_not_editable': 'vendor.import.err.notEditable',
  'not_ready': 'vendor.import.err.notReady',
  'nothing_to_retry': 'vendor.import.err.nothingToRetry',
  'not_discardable': 'vendor.import.err.notDiscardable',
  'profile_import_owner_only': 'vendor.import.profileOwnerOnly',
  'vendor_permission_forbidden': 'vendor.import.err.permission',
  'vendor_suspended': 'vendor.import.err.suspended',
  'account_suspended': 'vendor.import.err.suspended',
  'feature_disabled': 'vendor.import.err.disabled',
  'import_quota': 'vendor.import.err.quota',
  'empty_file': 'vendor.import.err.empty',
};

/// What to tell the vendor about [error], in [lang] (`en` | `sw`). [t] reads
/// the app's i18n. Never a raw code and never a stack trace.
String importErrorText(
  Object error, {
  required String lang,
  required String Function(String key) t,
}) {
  if (error is! ApiException) return t('vendor.import.err.network');
  final body = _body(error);
  final main = LocalText.from(body['message'])?.of(lang);
  if (main != null) {
    final why = LocalText.from(body['reasonMessage'])?.of(lang);
    return why != null && why != main ? '$main $why' : main;
  }
  final code = error.code;
  final key = code == null ? null : _keyForCode[code];
  if (key != null) return t(key);
  if (error.status == 499) return t('vendor.import.err.aborted');
  if (error.status == 429) return t('vendor.import.err.rateLimited');
  if (error.status == 413) return t('vendor.import.err.tooLarge');
  if (error.status >= 500) return t('vendor.import.err.server');
  return t('vendor.import.err.generic');
}

/// A refusal that means "the batch is gone or the tool is off": the page
/// cannot go on.
bool importErrorIsFatal(Object? error) => const {
  'import_not_found',
  'feature_disabled',
  'vendor_permission_forbidden',
  'vendor_suspended',
  'account_suspended',
}.contains(importErrorCode(error));
