import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'banner_models.dart';
import 'merch_back_button.dart';

/// The vendor's Promotions page (`/vendor/merch`, Shop home Phase 2 S1):
/// their banner proposals by state, with Edit / Withdraw / Send for
/// approval / Copy to new, and "Propose a banner".
///
/// Shown only while GET /vendor/tools/options says `merch.banners: true`
/// (SHOP_BANNERS); otherwise "This tool isn't available yet". A vendor
/// waiting for business approval sees why they cannot propose yet; staff
/// need the `products` permission.
class VendorBannersPage extends StatefulWidget {
  const VendorBannersPage({
    super.key,
    this.now,
    this.item,
    this.embedded = false,
  });

  /// Inside the Promotions page's "Flash sales | Banners" (Phase 2 S4): no
  /// app bar of its own.
  final bool embedded;

  /// The clock (tests).
  final DateTime Function()? now;

  /// A banner to scroll to and highlight (`?item=`, from a notification).
  final String? item;

  @override
  State<VendorBannersPage> createState() => _VendorBannersPageState();
}

class _VendorBannersPageState extends State<VendorBannersPage> {
  bool _loading = true;
  bool _unavailable = false;
  Object? _error;
  List<VendorBanner> _banners = const [];
  List<Map<String, dynamic>> _products = const [];
  final Set<String> _busy = {};

  /// The banner a notification pointed at, shown once the list is in.
  String? _highlight;
  bool _itemHandled = false;
  final _itemKey = GlobalKey(debugLabel: 'merch-item');

  /// Pages read at most (100 each): a vendor never has this many.
  static const _maxPages = 20;

  /// From the list's `vendor`: whether this business may propose now, and
  /// why not (`vendor_suspended`, `vendor_not_approved`).
  bool _canPropose = true;

  /// The business is suspended (403 account_suspended).
  bool _suspended = false;
  String? _cannotReason;

  /// `openProposals {open, max}`: Propose is off at the limit.
  int? _open;
  int? _maxOpen;
  bool get _atLimit => _open != null && _maxOpen != null && _open! >= _maxOpen!;

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  bool get _pendingVendor {
    final auth = AppScope.of(context).auth;
    return auth.isPendingApproval && auth.user?['userType'] == 'vendor';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    final tools = await VendorToolsOptions.of(context, refresh: refresh);
    if (!mounted) return;
    if (tools.suspended) {
      // 403 account_suspended: the suspended alert, nothing to propose.
      setState(() {
        _suspended = true;
        _canPropose = false;
        _cannotReason = 'vendor_suspended';
        _loading = false;
      });
      return;
    }
    if (!tools.banners) {
      setState(() {
        _unavailable = true;
        _loading = false;
      });
      return;
    }
    if (!canManageProducts(context)) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait<Object?>([
        _allBanners(api),
        api.vendorProducts().catchError((Object _) => <dynamic>[]),
      ]);
      if (!mounted) return;
      final list = results[0] as Map<String, dynamic>;
      final vendor = list['vendor'] is Map ? list['vendor'] as Map : const {};
      setState(() {
        // A vendor still waiting for approval cannot propose, whatever an
        // older server says.
        _canPropose = vendor['canPropose'] != false && !_pendingVendor;
        _cannotReason = _pendingVendor
            ? 'vendor_not_approved'
            : vendor['reason']?.toString();
        final open = list['openProposals'] is Map
            ? list['openProposals'] as Map
            : const {};
        _open = open['open'] is num ? (open['open'] as num).toInt() : null;
        _maxOpen = open['max'] is num ? (open['max'] as num).toInt() : null;
        _banners = (list['items'] is List ? list['items'] as List : const [])
            .whereType<Map>()
            .map((b) => VendorBanner.fromJson(Map<String, dynamic>.from(b)))
            .where((b) => b.id.isNotEmpty)
            .toList();
        _products = (results[1] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _unavailable = false;
        _loading = false;
      });
      _showItem();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _unavailable = e.status == 404 && e.code == 'feature_disabled';
        _error = _unavailable ? null : e;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Every page of the vendor's banners (limit 100, following nextCursor).
  /// The first page's `vendor` block is kept.
  static Future<Map<String, dynamic>> _allBanners(ApiClient api) async {
    final first = await api.vendorShopBanners();
    final items = [...?(first['items'] as List?)];
    var cursor = first['nextCursor']?.toString();
    for (var page = 1; page < _maxPages && (cursor ?? '').isNotEmpty; page++) {
      final next = await api.vendorShopBanners(cursor: cursor);
      items.addAll((next['items'] as List?) ?? const []);
      final more = next['nextCursor']?.toString();
      if (more == cursor) break;
      cursor = more;
    }
    return {...first, 'items': items};
  }

  /// After the first load: scroll to the notified banner and highlight it,
  /// or say it is not available.
  void _showItem() {
    final id = widget.item;
    if (_itemHandled || id == null || id.isEmpty) return;
    _itemHandled = true;
    if (!_banners.any((b) => b.id == id)) {
      FFSnack.info(context, context.tr('merch.notYours'));
      return;
    }
    setState(() => _highlight = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _itemKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: MediaQuery.disableAnimationsOf(target)
            ? Duration.zero
            : FFTokens.motionMedium,
      );
    });
  }

  /// The form has its own address (/vendor/merch/banner/new, /:id/edit),
  /// so a refresh brings it back.
  Future<void> _openForm({VendorBanner? banner, VendorBanner? copy}) async {
    final path = banner != null
        ? AppRoutes.vendorMerchEdit(banner.id)
        : copy != null
        ? '${AppRoutes.vendorMerchNew}?copy=${Uri.encodeQueryComponent(copy.id)}'
        : AppRoutes.vendorMerchNew;
    final sent = await context.push<bool>(path);
    if (sent == true && mounted) await _load();
  }

  Future<void> _withdraw(VendorBanner banner) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('merch.withdraw.title'),
      message: context.tr('merch.withdraw.body'),
      confirmLabel: context.tr('merch.withdraw.confirm'),
      cancelLabel: context.tr('merch.withdraw.keep'),
      destructive: true,
      confirmKey: const Key('merch-withdraw-confirm'),
    );
    if (!ok || !mounted) return;
    await _act(
      banner,
      () => AppScope.of(context).api.vendorWithdrawShopBanner(banner.id),
      'merch.withdrawn',
    );
  }

  Future<void> _end(VendorBanner banner) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('merch.endBanner.title'),
      message: context.tr('merch.endBanner.body'),
      confirmLabel: context.tr('merch.endBanner.confirm'),
      cancelLabel: context.tr('merch.withdraw.keep'),
      destructive: true,
      confirmKey: const Key('merch-end-confirm'),
    );
    if (!ok || !mounted) return;
    await _act(
      banner,
      () => AppScope.of(context).api.vendorEndShopBanner(banner.id),
      'merch.ended',
    );
  }

  Future<void> _submit(VendorBanner banner) => _act(
    banner,
    () => AppScope.of(context).api.vendorSubmitShopBanner(banner.id),
    'merch.sent',
  );

  /// Runs a list action, then reloads. A banner that can no longer change
  /// (409 not_editable) says so; a field problem sends the vendor to Edit.
  Future<void> _act(
    VendorBanner banner,
    Future<Object?> Function() call,
    String doneKey,
  ) async {
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy.add(banner.id));
    try {
      await call();
      messenger.success(locale.t(doneKey));
    } on ApiException catch (e) {
      messenger.error(locale.t(_actionError(e)));
    } catch (e) {
      messenger.error(
        locale.t(
          isNetworkError(e) ? 'merch.notSentOffline' : 'merch.saveFailed',
        ),
      );
    }
    if (!mounted) return;
    setState(() => _busy.remove(banner.id));
    await _load();
  }

  /// What a refused list action says. A banner with a field problem is
  /// fixed with Edit.
  static String _actionError(ApiException e) => switch (e.code) {
    'not_editable' ||
    'invalid_transition' ||
    'proposal_expired' => 'merch.notEditable',
    'feature_disabled' => 'merch.unavailable',
    'banner_not_found' => 'merch.notYours',
    'vendor_suspended' => 'merch.suspended',
    'vendor_not_approved' => 'merch.pendingBody',
    'price_claim_in_text' => 'merch.banner.noPrices',
    'contact_in_text' => 'merch.banner.noLinks',
    'target_not_owned' ||
    'target_type_not_allowed' => 'merch.banner.targetNotOwned',
    'target_not_eligible' => targetIneligibleKey(e.body),
    'target_required' => 'merch.banner.productRequired',
    'start_too_soon' => 'merch.dates.startSoon',
    'image_required' => 'merch.banner.imageRequired',
    'image_people_unconfirmed' => 'merch.banner.reconfirm',
    'rate_limited' => 'merch.rateLimited',
    'too_many_open_proposals' => 'merch.tooManyOpen',
    _ => 'merch.saveFailed',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _body(context),
      );
    }
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
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _body(context),
      ),
    );
  }

  // A vendor has a handful of banners: built at once, always scrollable
  // (pull to refresh works on short lists too).
  Widget _scroll(List<Widget> children) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) {
      return _scroll([
        FFSkeletonList(
          key: const Key('merch-loading'),
          semanticLabel: context.tr('common.loading'),
        ),
      ]);
    }
    if (_suspended) {
      return _scroll([
        FFAlert(
          key: const Key('merch-cannot-propose'),
          tone: FFAlertTone.error,
          message: context.tr('merch.suspended'),
        ),
      ]);
    }
    if (_unavailable) {
      return _scroll([
        FFEmptyState(
          key: const Key('merch-unavailable'),
          icon: Icons.campaign_outlined,
          title: context.tr('merch.unavailable'),
          action: FFButton(
            label: context.tr('merch.back'),
            variant: FFButtonVariant.secondary,
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.vendorHome),
          ),
        ),
      ]);
    }
    if (!canManageProducts(context)) {
      return _scroll([
        FFEmptyState(
          key: const Key('merch-restricted'),
          title: context.tr('vendor.noAccess'),
        ),
      ]);
    }
    final error = _error;
    if (error != null) {
      final offline = isNetworkError(error);
      return _scroll([
        FFErrorState(
          key: Key(offline ? 'merch-offline' : 'merch-error'),
          icon: offline ? Icons.wifi_off : Icons.error_outline,
          title: context.tr(
            offline ? 'merch.offlineTitle' : 'merch.banners.error',
          ),
          message: offline ? context.tr('merch.offlineBody') : null,
          onRetry: _load,
        ),
      ]);
    }
    final Widget propose = _canPropose
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FFButton(
                key: const Key('merch-propose'),
                label: context.tr('merch.banners.propose'),
                icon: Icons.add,
                fullWidth: true,
                visualDensity: VisualDensity.standard,
                maxLines: 2,
                onPressed: _atLimit ? null : () => _openForm(),
              ),
              if (_open != null && _maxOpen != null) ...[
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context
                      .tr(_atLimit ? 'merch.openFull' : 'merch.openCount')
                      .replaceAll('{open}', '$_open')
                      .replaceAll('{max}', '$_maxOpen'),
                  key: const Key('merch-open-count'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          )
        : _cannotReason == 'vendor_suspended'
        ? FFAlert(
            key: const Key('merch-cannot-propose'),
            tone: FFAlertTone.error,
            message: context.tr('merch.suspended'),
          )
        // Waiting for business approval (spec §5.2.2): why, and where to
        // finish it.
        : FFEmptyState(
            key: const Key('merch-pending'),
            icon: Icons.hourglass_empty,
            title: context.tr('merch.pendingTitle'),
            body: context.tr('merch.pendingBody'),
            action: FFButton(
              key: const Key('merch-open-verification'),
              label: context.tr('merch.openVerification'),
              variant: FFButtonVariant.secondary,
              icon: Icons.verified_user_outlined,
              visualDensity: VisualDensity.standard,
              maxLines: 2,
              onPressed: () => context.push(AppRoutes.verification),
            ),
          );
    if (_banners.isEmpty && !_canPropose) return _scroll([propose]);
    if (_banners.isEmpty) {
      return _scroll([
        FFEmptyState(
          key: const Key('merch-empty'),
          icon: Icons.campaign_outlined,
          title: context.tr('merch.banners.emptyTitle'),
          body: context.tr('merch.banners.emptyBody'),
          action: propose,
        ),
      ]);
    }
    final now = _now;
    final groups = {
      for (final g in bannerGroups)
        g: _banners.where((b) => bannerGroup(b.status) == g).toList(),
    };
    final theme = Theme.of(context);
    return _scroll([
      Semantics(
        header: true,
        child: Text(
          context.tr('merch.banners.title'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      propose,
      for (final g in bannerGroups)
        if (groups[g]!.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingLg),
          Semantics(
            header: true,
            child: Text(
              context.tr('merch.group.$g'),
              key: Key('merch-group-$g'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final b in groups[g]!) _card(context, b, now),
        ],
    ]);
  }

  String _productName(VendorBanner b) {
    final known = _products
        .where((p) => p['id']?.toString() == b.targetValue)
        .map((p) => p['name']?.toString() ?? '')
        .firstOrNull;
    return (known == null || known.isEmpty) ? (b.targetName ?? '') : known;
  }

  String _when(DateTime? at) {
    if (at == null) return '-';
    return formatDateTime(
      toEatWallClock(at),
      locale: FFLocaleScope.of(context).locale.languageCode,
    );
  }

  /// The line under the status (spec §4.2).
  String? _extraLine(BuildContext context, VendorBanner b, String status) {
    String fill(String key, String name, String value) =>
        context.tr(key).replaceAll('{$name}', value);
    switch (status) {
      case 'draft':
        return context.tr('merch.line.notSent');
      case 'pending_approval':
        // The server's expiresAt is already the earlier of 14 days and the
        // start.
        final expires = b.expiresAt;
        if (expires == null) return null;
        return fill('merch.line.expires', 'date', _when(expires));
      case 'approved':
        return fill('merch.line.starts', 'date', _when(b.startsAt));
      case 'live':
        return fill('merch.line.ends', 'date', _when(b.endsAt));
      case 'ended':
        if (b.endedByFitflex || b.reasonCode == 'ended_by_fitflex') {
          // "Ended {date} by FitFlex: {reason}" (spec §4.2).
          final note = b.reasonNote?.trim() ?? '';
          return context
              .tr(
                note.isEmpty
                    ? 'merch.line.endedByFitflexNoReason'
                    : 'merch.line.endedByFitflex',
              )
              .replaceAll('{date}', _when(b.endedAt ?? b.endsAt))
              .replaceAll('{reason}', note);
        }
        return fill('merch.line.endedOn', 'date', _when(b.endedAt ?? b.endsAt));
      case 'rejected':
        // The reason's label in the user's language, then staff's note.
        final label = b.rejectLabelKey == null
            ? null
            : context.tr(b.rejectLabelKey!);
        final reason = [
          ?label,
          ?b.reasonNote,
        ].where((s) => s.trim().isNotEmpty).join('. ');
        return reason.isEmpty
            ? null
            : fill('merch.line.reason', 'reason', reason);
      case 'expired':
        return context.tr('merch.line.notReviewed');
      case 'withdrawn':
        return context.tr('merch.line.youWithdrew');
    }
    return null;
  }

  static FFBadgeTone _tone(String status) => switch (status) {
    'pending_approval' => FFBadgeTone.warning,
    // Scheduled in info blue, Live in success green (QA S4 #10).
    'approved' => FFBadgeTone.info,
    'live' => FFBadgeTone.success,
    'rejected' => FFBadgeTone.danger,
    'ended' => FFBadgeTone.defaultTone,
    _ => FFBadgeTone.gray,
  };

  Widget _card(BuildContext context, VendorBanner b, DateTime now) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final status = b.status;
    final headline = b.headline(lang);
    final extra = _extraLine(context, b, status);
    final busy = _busy.contains(b.id);
    final scope = AppScope.of(context);
    final public = b.publicImage.resolved(scope.api.baseUrl).pick(160, 2);
    // Before approval only the private preview exists (needs the session).
    final thumb =
        public ??
        (b.previewUrl.isEmpty
            ? ''
            : '${scope.api.baseUrl}${b.previewUrl}?w=240');
    final token = scope.auth.token;
    final product = _productName(b);
    final target = b.targetType == 'vendor_store'
        ? context.tr('merch.line.linksStore')
        : context
              .tr('merch.line.linksProduct')
              .replaceAll('{product}', product.isEmpty ? '-' : product);
    Widget action(String key, String label, String a11y, VoidCallback onTap) =>
        Semantics(
          button: true,
          excludeSemantics: true,
          label: context.tr(a11y).replaceAll('{headline}', headline),
          onTap: busy ? null : onTap,
          child: FFButton(
            key: Key('merch-$key-${b.id}'),
            label: context.tr(label),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: busy ? null : onTap,
          ),
        );
    final actions = <Widget>[
      if (b.canSubmit && _canPropose)
        action(
          'submit',
          'merch.send',
          'merch.action.a11ySubmit',
          () => _submit(b),
        ),
      if (b.canEdit && _canPropose)
        action(
          'edit',
          'merch.action.edit',
          'merch.action.a11yEdit',
          () => _openForm(banner: b),
        ),
      if (b.canWithdraw)
        action(
          'withdraw',
          'merch.action.withdraw',
          'merch.action.a11yWithdraw',
          () => _withdraw(b),
        ),
      if (b.canEnd)
        action(
          'end',
          'merch.action.endNow',
          'merch.action.a11yEnd',
          () => _end(b),
        ),
      if (bannerGroup(status) == 'past' && _canPropose)
        action(
          'copy',
          'merch.action.copy',
          'merch.action.a11yCopy',
          () => _openForm(copy: b),
        ),
    ];
    final highlighted = _highlight == b.id;
    final card = FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                  child: SizedBox(
                    width: 96,
                    height: 60,
                    child: ColoredBox(
                      color: FFTokens.heroPlaceholder,
                      child: thumb.isEmpty
                          ? const SizedBox.expand()
                          : FFRemoteImage(
                              src: thumb,
                              headers: public == null && token != null
                                  ? {'authorization': 'Bearer $token'}
                                  : null,
                              width: 96,
                              height: 60,
                              fit: BoxFit.cover,
                              fallback: const SizedBox.expand(),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline.isEmpty ? '-' : headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    FFBadge(
                      key: Key('merch-status-${b.id}'),
                      label: context.tr(bannerStatusKey(status)),
                      tone: _tone(status),
                      wrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (extra != null)
            Text(
              extra,
              key: Key('merch-line-${b.id}'),
              style: theme.textTheme.bodyMedium,
            ),
          Text(
            '${_when(b.startsAt)} – ${_when(b.endsAt)} '
            '(${context.tr('merch.dates.tzNote')})',
            style: theme.textTheme.bodySmall,
          ),
          Text(target, style: theme.textTheme.bodySmall),
          Text(
            context
                .tr('merch.line.shownTo')
                .replaceAll(
                  '{audiences}',
                  b.audienceRoles
                      .map((a) => context.tr('merch.audience.$a'))
                      .join(', '),
                ),
            style: theme.textTheme.bodySmall,
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(spacing: FFTokens.spacingXs, children: actions),
          ],
        ],
      ),
    );
    return Padding(
      key: Key('merch-banner-${b.id}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: KeyedSubtree(
        key: highlighted ? _itemKey : null,
        // The banner a notification is about: a brand outline, and it is
        // the one scrolled to (not colour alone).
        child: highlighted
            ? DecoratedBox(
                key: Key('merch-highlight-${b.id}'),
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                ),
                child: card,
              )
            : card,
      ),
    );
  }
}
