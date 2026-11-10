import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'merch_back_button.dart';
import 'vendor_banners_page.dart';
import 'vendor_flash_sales_page.dart';

/// The vendor's Promotions page (`/vendor/merch`): "Flash sales | Banners"
/// (spec §5.2.1, `?tab=sales|banners`). Each tab shows only while the
/// server reports its tool (`merch.flashSales`, `merch.banners`).
///
/// With flash sales off this is exactly the banners page it was before
/// (Phase 2 S1), states included.
class VendorMerchPage extends StatefulWidget {
  const VendorMerchPage({super.key, this.tab, this.item, this.now});

  /// `sales` or `banners` (from the address); the first available
  /// otherwise.
  final String? tab;

  /// A proposal to scroll to (`?item=`, from a notification), in [tab].
  final String? item;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<VendorMerchPage> createState() => _VendorMerchPageState();
}

class _VendorMerchPageState extends State<VendorMerchPage> {
  VendorTools? _tools;

  /// The tab the address asked for. A link with an item but no tab is a
  /// banner notification from before flash sales (`?item=<bannerId>`).
  late final String _asked = widget.tab == 'sales'
      ? 'sales'
      : widget.tab == 'banners' || (widget.item ?? '').isNotEmpty
      ? 'banners'
      : 'sales';
  late String _tab = _asked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTools());
  }

  Future<void> _loadTools() async {
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    setState(() {
      _tools = tools;
      if (!tools.flashSales) _tab = 'banners';
      if (!tools.banners && tools.flashSales) _tab = 'sales';
    });
  }

  @override
  Widget build(BuildContext context) {
    final tools = _tools;
    // Flash sales off (or not known to be on): the banners page as before,
    // with its own unavailable / suspended / restricted states.
    if (tools != null && !tools.flashSales) {
      return VendorBannersPage(item: widget.item, now: widget.now);
    }
    final both = tools != null && tools.banners && tools.flashSales;
    return Scaffold(
      appBar: AppBar(
        leading: const MerchBackButton(),
        // Long Swahili at 130% wraps to a second line instead of "…".
        toolbarHeight: math.max(
          kToolbarHeight,
          2 * MediaQuery.textScalerOf(context).scale(22) + 16,
        ),
        title: Text(
          context.tr('merch.entry.title'),
          key: const Key('merch-title'),
          maxLines: 2,
          softWrap: true,
        ),
      ),
      body: tools == null
          ? Padding(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              child: FFSkeletonList(
                key: const Key('merch-loading'),
                semanticLabel: context.tr('common.loading'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (both)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FFTokens.spacingLg,
                      FFTokens.spacingSm,
                      FFTokens.spacingLg,
                      0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: FFSegmented(
                          key: const Key('merch-tabs'),
                          value: _tab,
                          options: [
                            ('sales', context.tr('merch.tab.sales')),
                            ('banners', context.tr('merch.tab.banners')),
                          ],
                          onChanged: (v) => setState(() => _tab = v),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _tab == 'sales'
                      ? VendorFlashSalesPage(
                          key: const Key('merch-tab-sales'),
                          item: _asked == 'sales' ? widget.item : null,
                          now: widget.now,
                        )
                      : VendorBannersPage(
                          key: const Key('merch-tab-banners'),
                          embedded: true,
                          item: _asked == 'banners' ? widget.item : null,
                          now: widget.now,
                        ),
                ),
              ],
            ),
    );
  }
}
