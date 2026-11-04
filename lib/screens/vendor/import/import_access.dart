// Vendor smart import V3: who may open the import screens. Fails closed: the
// tool must be on (exactly `true` from GET /vendor/tools/options) and the
// person needs the staff permission `import`. With the tool off a screen
// just leaves for the vendor home, as the other gated vendor tools do.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/i18n.dart';
import '../purchases/purchase_models.dart' show refreshVendorAccess;
import '../stock/stock_options.dart';
import 'import_models.dart';

/// What the screens know about the signed-in person.
class ImportAccess {
  const ImportAccess({required this.tools, required this.isOwner});
  final VendorTools tools;

  /// The vendor account holder (the only one who may import the profile).
  final bool isOwner;
}

/// The entry point and routes open: tool on AND `import` permission.
bool importEntryShown(BuildContext context, VendorTools tools) =>
    importOpen(tools, canImport: canVendor(context, 'import'));

/// Checks an import route may open. Otherwise leaves (silently when the tool
/// is off; "no access" without the permission) and answers null.
Future<ImportAccess?> enterImportRoute(BuildContext context) async {
  final tools = await VendorToolsOptions.of(context);
  if (!context.mounted) return null;
  if (!tools.dataImport) {
    context.go('/vendor/home');
    return null;
  }
  // The session may predate the grant of `import`: ask the server's stored
  // staff record once before refusing. If /vendor/me cannot be read the
  // session's own permissions stand, so this fails closed.
  if (!canVendor(context, 'import')) await refreshVendorAccess(context);
  if (!context.mounted) return null;
  if (!canVendor(context, 'import')) {
    FFSnack.error(context, context.tr('vendor.import.noAccess'));
    context.go('/vendor/home');
    return null;
  }
  final user = AppScope.of(context).auth.user;
  return ImportAccess(tools: tools, isOwner: user?['userType'] == 'vendor');
}
