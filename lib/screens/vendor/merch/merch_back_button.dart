import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/i18n.dart';

/// The Promotions page's back arrow ("Banners & flash sales").
///
/// Always shown: the page is often opened with `context.go` (after saving a
/// banner or a sale), by a web reload or by a notification link, and then
/// there is nothing to pop. Pops when it can, otherwise goes to the vendor
/// home (where the page is opened from).
class MerchBackButton extends StatelessWidget {
  const MerchBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('merch-back'),
    tooltip: context.tr('a11y.back'),
    icon: const Icon(Icons.arrow_back),
    onPressed: () =>
        context.canPop() ? context.pop() : context.go(AppRoutes.vendorHome),
  );
}
