// Partner DOB slice 4: in trainer and owner shop modes, a Trainer or gym
// owner with no date of birth is told that only purchases are used, and is
// offered the Slice 3 sheet to add one.
//
// Server-driven: shown only where personalisation is already available,
// GET/PUT /shop/preferences says `profileSignals: true` (the server uses a
// partner's own date of birth in this mode; absent on older servers and
// with a flag off) and GET /me/personal-details says `ask` (a partner role,
// no date of birth). Never shown when a date of birth is known, so never to
// an under-18 (whose shop personalisation is unavailable anyway).
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../partner_details.dart';
import '../../shop_home.dart';
import '../partner_details_widgets.dart';

/// Trainer and owner shop modes: the ones that use the partner's own date
/// of birth (Person) for gender/age.
bool isPartnerShopMode(String? mode) =>
    mode == ShopHomeMode.trainer.wire || mode == ShopHomeMode.owner.wire;

/// The switch hint key for a trainer's or owner's own [uses] (review
/// round 1): gender in use → age and gender; age only → age; plus the
/// trainer specialties and the area when listed. Null when neither gender
/// nor age is in [uses] (the purchases-only hint applies).
String? partnerSwitchHintKey(Set<ShopSignal>? uses, {required bool area}) {
  if (uses == null) return null;
  final String base;
  if (uses.contains(ShopSignal.gender)) {
    base = 'Gender';
  } else if (uses.contains(ShopSignal.age)) {
    base = 'Age';
  } else {
    return null;
  }
  final specialty = uses.contains(ShopSignal.specialty) ? 'Specialty' : '';
  return 'shop.why.switchHintPartner$base$specialty${area ? 'Area' : ''}';
}

/// Whether [uses] names gender or age.
bool usesProfileSignals(Set<ShopSignal>? uses) =>
    (uses?.contains(ShopSignal.gender) ?? false) ||
    (uses?.contains(ShopSignal.age) ?? false);

/// Whether the hint may show for [details].
bool partnerDobHintApplies(PersonalDetails? details) =>
    details != null &&
    details.ask &&
    details.dateOfBirth == null &&
    !isUnderPartnerAge(details.dateOfBirth);

class ShopPartnerDobHint extends StatefulWidget {
  const ShopPartnerDobHint({
    super.key,
    required this.mode,
    required this.profileSignals,
    this.onSaved,
  });

  /// `trainer` or `owner`; anything else shows nothing.
  final String? mode;

  /// [ShopPreferences.profileSignals]: false shows nothing and asks the
  /// server nothing.
  final bool profileSignals;

  /// A date of birth was saved (the shop may reload).
  final VoidCallback? onSaved;

  @override
  State<ShopPartnerDobHint> createState() => _ShopPartnerDobHintState();
}

class _ShopPartnerDobHintState extends State<ShopPartnerDobHint> {
  PersonalDetails? _details;
  String? _account;
  bool _started = false;

  bool get _wanted => widget.profileSignals && isPartnerShopMode(widget.mode);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  @override
  void didUpdateWidget(ShopPartnerDobHint old) {
    super.didUpdateWidget(old);
    // The preferences can arrive after the sheet opened.
    _start();
  }

  void _start() {
    if (_started || !_wanted) return;
    _started = true;
    final auth = AppScope.of(context).auth;
    final id = auth.user?['id']?.toString() ?? '';
    if (auth.token == null || id.isEmpty) return;
    _account = id;
    PartnerDetailsSession.current.addListener(_onSession);
    _load();
  }

  @override
  void dispose() {
    PartnerDetailsSession.current.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final details = PartnerDetailsSession.current.value;
    if (details != null && mounted) setState(() => _details = details);
  }

  Future<void> _load() async {
    final details = await PartnerDetailsSession.load(
      AppScope.of(context).api,
      _account!,
    );
    if (mounted) setState(() => _details = details);
  }

  Future<void> _add() async {
    final details = _details;
    if (details == null) return;
    final saved = FFLocaleScope.of(context).t('partnerDob.saved');
    final result = await showPartnerDetailsSheet(
      context,
      details: details,
      // Gym owners choose their gender in the sheet; a Trainer's comes
      // from the trainer profile (read-only there).
      canEditGender: widget.mode == ShopHomeMode.owner.wire,
      role: widget.mode == ShopHomeMode.owner.wire
          ? PartnerRole.owner
          : PartnerRole.trainer,
    );
    if (result == null || !mounted) return;
    PartnerDetailsSession.saved(_account!, result);
    setState(() => _details = result);
    FFSnack.success(context, saved);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_wanted || !partnerDobHintApplies(_details)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Column(
        key: const Key('shop-partner-dob-hint'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('shop.partnerDob.hint'),
            style: theme.textTheme.bodyMedium,
          ),
          FFButton(
            key: const Key('shop-partner-dob-add'),
            label: context.tr('partnerDob.promptTitle'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            // Wraps instead of cutting off at large text (Swahili is long).
            maxLines: 3,
            onPressed: _add,
          ),
        ],
      ),
    );
  }
}
