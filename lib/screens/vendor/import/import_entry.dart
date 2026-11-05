// Vendor smart import V3: the "Import business data" item on the Business
// tab. The tab shows it only when `importEntryShown` says so.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'import_routes.dart';

class VendorImportEntryTile extends StatelessWidget {
  const VendorImportEntryTile({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: FFTokens.spacingMd),
    child: FFActionTile(
      key: const Key('vendor-import-entry'),
      icon: Icons.upload_file_outlined,
      title: context.tr('vendor.import.tile'),
      subtitle: context.tr('vendor.import.tileSubtitle'),
      onTap: () => context.push(vendorImportRoute),
    ),
  );
}
