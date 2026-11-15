// Shop Phase 2 S2: the "Personalised shop" switch (Why sheet and member
// Privacy page) and the Privacy page tile. Spec: docs/design/
// shop-home-phase2.md §6.3–6.4 and shop-home.md §8.2.
//
// Contract: GET /shop/preferences → {personalised, available}; PUT the same
// path with {personalised, source}. A 404 (feature_disabled) or a non-JSON
// answer means personalisation does not exist on this backend, and every
// control here hides itself.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../api_client.dart';
import '../../api_error_message.dart';
import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../network/browser_online.dart';
import '../../shop_home.dart';
import '../../shop_near_you.dart';
import '../../partner_details.dart' show PartnerRole;
import '../partner_details_widgets.dart';
import 'shop_partner_dob_hint.dart';
import 'shop_near_you_ui.dart';
import 'shop_focus_ring.dart';

/// The Why and Privacy sheets: a bottom sheet on phones and tablets, a
/// centred dialog 480 wide from 1024 px (spec §12).
Future<T?> showShopSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) => showFFSheet<T>(
  context,
  title: title,
  wideDialogWidth: 480,
  child: child,
);

/// Whether this failure means "there is no personalisation here".
bool shopPersonalisationMissing(Object error) =>
    error is FormatException || (error is ApiException && error.status == 404);

/// The "Personalised shop" switch row. Saves at once with an optimistic
/// update: the switch moves, is disabled with a spinner while saving, and
/// goes back (with "Couldn't save. Try again." under it, once) if the save
/// fails. "Shop updated" is said under the switch too, not in a snackbar
/// (which would cover the sheet's link).
///
/// One keyboard stop for the whole row (the switch itself is not a second
/// one), with the two-tone focus ring.
///
/// [initial] is the value already known (from GET /shop/home); null loads it
/// from GET /shop/preferences first. When the backend has no preferences, or
/// says they are not available for this account, nothing is shown.
class ShopPersonalisedSwitch extends StatefulWidget {
  const ShopPersonalisedSwitch({
    super.key,
    required this.source,
    this.mode,
    this.initial,
    this.partnerHint = false,
    this.partnerUses,
    this.areaHint = false,
    this.onChanged,
    this.onUnavailable,
  });

  /// Phase 2 S3: near-you can be used, so the hint also names "my current
  /// area".
  final bool areaHint;

  /// `privacy_page` or `why_sheet` (sent with the PUT).
  final String source;

  /// The role being shopped as (`member`, `trainer`, ...), sent as `?mode=`.
  final String? mode;
  final bool? initial;

  /// Not member mode: the partner hint (purchases).
  final bool partnerHint;

  /// Partner DOB slice 4: with [partnerHint], the last `uses` that named
  /// profile_gender / profile_age for this trainer or owner (their own date
  /// of birth). The hint then names exactly those (and specialties).
  final Set<ShopSignal>? partnerUses;

  /// Called with the server's answer after a successful save.
  final ValueChanged<ShopPreferences>? onChanged;

  /// The save answered 404 (SHOP_PERSONALISATION was switched off): the
  /// switch hides itself and says so here.
  final VoidCallback? onUnavailable;

  @override
  State<ShopPersonalisedSwitch> createState() => _ShopPersonalisedSwitchState();
}

class _ShopPersonalisedSwitchState extends State<ShopPersonalisedSwitch> {
  bool? _value;
  bool _loading = false;
  bool _loadFailed = false;
  bool _hidden = false;
  bool _saving = false;
  bool _saveFailed = false;
  bool _saved = false;

  /// The switch is drawn but never focused: the row is the one stop.
  final FocusNode _switchFocus = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void dispose() {
    _switchFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    if (_value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final prefs = ShopPreferences.fromJson(
        await AppScope.of(context).api.shopPreferences(mode: widget.mode),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hidden = !prefs.available;
        _value = prefs.personalised;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hidden = shopPersonalisationMissing(e);
        _loadFailed = !_hidden;
      });
    }
  }

  Future<void> _set(bool next) async {
    final before = _value ?? true;
    if (_saving || next == before) return;
    final api = AppScope.of(context).api;
    final uid = AppScope.of(context).auth.user?['id']?.toString();
    setState(() {
      _value = next;
      _saving = true;
      _saveFailed = false;
      _saved = false;
    });
    try {
      final prefs = ShopPreferences.fromJson(
        await api.updateShopPreferences(
          personalised: next,
          source: widget.source,
          mode: widget.mode,
        ),
      );
      // Off also turns near-you off: the area kept on this device for this
      // account is forgotten, and location is not read again (DD-P2-8).
      if (!prefs.personalised) await ShopNearYouStore.clear(uid);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
        _value = prefs.personalised;
      });
      widget.onChanged?.call(prefs);
    } catch (e) {
      if (!mounted) return;
      if (shopPersonalisationMissing(e)) {
        // Personalisation is gone (404 feature_disabled): nothing to save.
        setState(() {
          _saving = false;
          _hidden = true;
        });
        widget.onUnavailable?.call();
        return;
      }
      setState(() {
        _saving = false;
        _value = before;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final title = context.tr('shop.why.switch');
    final partnerKey = widget.partnerHint
        ? partnerSwitchHintKey(widget.partnerUses, area: widget.areaHint)
        : null;
    final hint = context.tr(
      partnerKey ??
          '${widget.partnerHint ? 'shop.why.switchHintPartner' : 'shop.why.switchHintMember'}'
              '${widget.areaHint ? 'Area' : ''}',
    );
    if (_loadFailed) {
      return Row(
        key: const Key('shop-why-personalised-failed'),
        children: [
          Expanded(
            child: Text(
              context.tr('shop.why.loadFailed'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          FFButton(
            key: const Key('shop-why-personalised-retry'),
            label: context.tr('common.retry'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _load,
          ),
        ],
      );
    }
    if (_loading || _value == null) {
      return Semantics(
        label: context.tr('privacy.shop.loading'),
        child: const ExcludeSemantics(
          child: SizedBox(height: 48, child: FFSkeletonLine()),
        ),
      );
    }
    final value = _value!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShopFocusRing(
          // Two-tone (white inside a dark ring): visible on light and dark
          // sheets alike.
          onPhoto: true,
          builder: (node) => MergeSemantics(
            child: InkWell(
              key: const Key('shop-why-personalised-row'),
              focusNode: node,
              onTap: _saving ? null : () => _set(!value),
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.bodyLarge),
                          Text(hint, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (_saving)
                      const Padding(
                        padding: EdgeInsets.only(left: FFTokens.spacingSm),
                        child: FFSpinner(size: 16),
                      ),
                    Switch(
                      key: const Key('shop-why-personalised'),
                      value: value,
                      focusNode: _switchFocus,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onChanged: _saving ? null : _set,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_saved && !_saving)
          Semantics(
            liveRegion: true,
            child: Text(
              context.tr('shop.why.saved'),
              key: const Key('shop-why-personalised-saved'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (_saveFailed)
          Semantics(
            liveRegion: true,
            child: Text(
              context.tr('shop.why.saveFailed'),
              key: const Key('shop-why-personalised-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// Privacy & data → "Personalised shop" (spec §6.4). Hidden when the
/// backend has no shop preferences (SHOP_PERSONALISATION off) or they are
/// not available for this account (under 18).
class ShopPrivacyTile extends StatefulWidget {
  const ShopPrivacyTile({super.key});

  @override
  State<ShopPrivacyTile> createState() => _ShopPrivacyTileState();
}

enum _TileState { loading, ready, failed, offline, hidden }

class _ShopPrivacyTileState extends State<ShopPrivacyTile> {
  static const _mode = 'member';
  _TileState _state = _TileState.loading;
  ShopPreferences _prefs = const ShopPreferences(
    personalised: true,
    available: false,
  );
  bool get _on => _prefs.personalised;

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onlineChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onlineChanged);
    super.dispose();
  }

  /// Offline is shown at once; coming back online loads again.
  void _onlineChanged() {
    if (!mounted) return;
    if (!BrowserOnline.instance.value) {
      if (_state != _TileState.hidden) {
        setState(() => _state = _TileState.offline);
      }
    } else if (_state == _TileState.offline) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!BrowserOnline.instance.value) {
      setState(() => _state = _TileState.offline);
      return;
    }
    setState(() => _state = _TileState.loading);
    try {
      final prefs = ShopPreferences.fromJson(
        await AppScope.of(context).api.shopPreferences(mode: _mode),
      );
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _state = prefs.available ? _TileState.ready : _TileState.hidden;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _state = shopPersonalisationMissing(e)
            ? _TileState.hidden
            : isNetworkError(e) || e is TimeoutException
            ? _TileState.offline
            : _TileState.failed,
      );
    }
  }

  Future<void> _open() async {
    await showShopSheet<void>(
      context,
      title: context.tr('privacy.shop.title'),
      child: ShopPrivacySheet(
        initial: _prefs,
        mode: _mode,
        onChanged: (prefs) {
          if (mounted) setState(() => _prefs = prefs);
        },
        onUnavailable: () {
          if (mounted) setState(() => _state = _TileState.hidden);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _TileState.hidden) return const SizedBox.shrink();
    final subtitle = switch (_state) {
      _TileState.loading => context.tr('privacy.shop.loading'),
      _TileState.failed => context.tr('privacy.shop.loadFailed'),
      _TileState.offline => context.tr('privacy.shop.offline'),
      _ => context.tr(_on ? 'privacy.shop.on' : 'privacy.shop.off'),
    };
    return FFActionTile(
      key: const Key('privacy-shop'),
      icon: Icons.storefront_outlined,
      title: context.tr('privacy.shop.title'),
      subtitle: subtitle,
      // Loading: a skeleton line, announced as "Loading your setting".
      subtitleWidget: _state == _TileState.loading
          ? Semantics(
              key: const Key('privacy-shop-loading'),
              label: subtitle,
              child: const ExcludeSemantics(
                child: FFSkeletonLine(widthFactor: 0.3),
              ),
            )
          : null,
      onTap: switch (_state) {
        _TileState.ready => _open,
        _TileState.failed => _load,
        // Offline: disabled, "Needs internet"; loads again once online.
        _ => null,
      },
    );
  }
}

/// The Privacy page sheet: the same switch, then only what is actually used
/// (the server's `uses`), what is never used, and the draft note.
class ShopPrivacySheet extends StatefulWidget {
  const ShopPrivacySheet({
    super.key,
    required this.initial,
    this.mode,
    this.onChanged,
    this.onUnavailable,
  });

  final ShopPreferences initial;
  final String? mode;
  final ValueChanged<ShopPreferences>? onChanged;
  final VoidCallback? onUnavailable;

  @override
  State<ShopPrivacySheet> createState() => _ShopPrivacySheetState();
}

class _ShopPrivacySheetState extends State<ShopPrivacySheet> {
  late ShopPreferences _prefs = widget.initial;
  bool _gone = false;

  /// Partner DOB slice 4: trainer and owner modes use the partner's own
  /// date of birth (and gender), worded as such.
  bool get _partner => isPartnerShopMode(widget.mode ?? _prefs.mode);

  /// The last `uses` naming gender or age while this sheet was open. Kept
  /// when the switch goes off (`uses` is then empty), so the switch hint
  /// does not change under the finger.
  late Set<ShopSignal>? _profileUses = usesProfileSignals(widget.initial.uses)
      ? widget.initial.uses
      : null;

  PartnerRole get _role => (widget.mode ?? _prefs.mode) == 'owner'
      ? PartnerRole.owner
      : PartnerRole.trainer;

  /// The server lists `location` in `uses` (SHOP_NEAR_YOU on and the
  /// switch on).
  bool get _location => _prefs.uses?.contains(ShopSignal.location) ?? false;

  /// The "What we use" lines, in the server's order, from `uses` only. A
  /// backend without `uses` lists nothing personal.
  List<String> _lines(BuildContext context) {
    final uses = _prefs.uses ?? const <ShopSignal>{};
    final months = _prefs.historyMonths ?? 12;
    final p = _partner ? 'Partner' : '';
    return [
      if (uses.contains(ShopSignal.purchaseHistory))
        months == 1
            ? context.tr('privacy.shop.usesHistoryOne')
            : context
                  .tr('privacy.shop.usesHistory')
                  .replaceAll('{months}', '$months'),
      if (uses.contains(ShopSignal.gender) && uses.contains(ShopSignal.age))
        context.tr('privacy.shop.usesGenderAge$p')
      else if (uses.contains(ShopSignal.gender))
        context.tr('privacy.shop.usesGender$p')
      else if (uses.contains(ShopSignal.age))
        context.tr('privacy.shop.usesAge$p'),
      if (uses.contains(ShopSignal.location))
        context.tr('privacy.shop.usesLocation'),
      if (uses.contains(ShopSignal.goal)) context.tr('privacy.shop.usesGoal'),
      if (uses.contains(ShopSignal.specialty))
        context.tr('privacy.shop.usesSpecialty'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_gone) return const SizedBox.shrink();
    final lines = _lines(context);
    final genderOrAge =
        (_prefs.uses?.contains(ShopSignal.gender) ?? false) ||
        (_prefs.uses?.contains(ShopSignal.age) ?? false);
    Widget bullet(String text, int i) => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('•  ', style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              text,
              key: Key('privacy-shop-use-$i'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const Key('privacy-shop-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShopPersonalisedSwitch(
          source: ShopPreferences.sourcePrivacyPage,
          mode: widget.mode,
          initial: _prefs.personalised,
          areaHint: _location,
          partnerHint: _partner,
          partnerUses: _partner ? _profileUses : null,
          onChanged: (prefs) {
            setState(() {
              _prefs = prefs;
              if (usesProfileSignals(prefs.uses)) _profileUses = prefs.uses;
            });
            widget.onChanged?.call(prefs);
          },
          onUnavailable: () {
            setState(() => _gone = true);
            widget.onUnavailable?.call();
          },
        ),
        // The draft note sits right under the switch (muted), so it is seen
        // without scrolling at 375 x 812 (QA 2026-10-22).
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            context.tr('privacy.shop.draft'),
            key: const Key('privacy-shop-draft'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Phase 2 S3: on, off or the area, with Turn on / Change / Turn off.
        if (_location && _prefs.personalised) ...[
          const SizedBox(height: FFTokens.spacingSm),
          const ShopNearYouLine(),
        ],
        // No `uses` from the server: no list (never a guess).
        if (_prefs.uses != null) ...[
          const SizedBox(height: FFTokens.spacingMd),
          Semantics(
            header: true,
            child: Text(
              context.tr('privacy.shop.usesTitle'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          if (lines.isEmpty)
            Text(
              context.tr('privacy.shop.usesNone'),
              key: const Key('privacy-shop-uses-none'),
              style: theme.textTheme.bodyMedium,
            )
          else
            for (var i = 0; i < lines.length; i++) bullet(lines[i], i),
        ],
        if (genderOrAge) ...[
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context.tr('privacy.shop.orderOnly'),
            key: const Key('privacy-shop-order-only'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (_partner) ...[
          // Slice 4: no date of birth → only purchases; offer to add one.
          ShopPartnerDobHint(
            mode: widget.mode ?? _prefs.mode,
            profileSignals: _prefs.profileSignals,
          ),
          // Slice 5: how the partner's date of birth is used (its own
          // "never" line names verification data too).
          const SizedBox(height: FFTokens.spacingMd),
          PartnerShopExplainer(
            role: _role,
            showTitle: true,
            showDraft: false,
          ),
        ] else ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('privacy.shop.never'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
