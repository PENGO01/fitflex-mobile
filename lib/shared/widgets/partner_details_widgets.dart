// Partner date of birth (plan slice 3): the date-of-birth field for the
// Trainer and gym-owner registration forms, the owner's optional gender
// field, the home prompt card, the settings tile and its edit sheet. Every
// piece shows nothing while GET /me/personal-details is off or fails.
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../components/components.dart';
import '../date_of_birth.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../partner_details.dart';

/// The signed-in account the device-side prompt counts belong to.
String? _accountOf(BuildContext context) {
  final auth = AppScope.of(context).auth;
  if (auth.token == null) return null;
  final id = auth.user?['id']?.toString() ?? '';
  return id.isEmpty ? null : id;
}

/// Date of birth for a Trainer or gym owner: picked from a calendar
/// (1901-01-01 to today in Dar), YYYY-MM-DD, 18 or older.
class PartnerDobField extends StatelessWidget {
  const PartnerDobField({
    super.key,
    required this.controller,
    required this.role,
    this.required = true,
    this.enabled = true,
    this.errorText,
    this.onChanged,
    this.showHelp = true,
  });

  final TextEditingController controller;

  /// Whose explanation "How we use it" opens.
  final PartnerRole role;
  final bool required;
  final bool enabled;

  /// A refusal from the server, shown under the field.
  final String? errorText;
  final VoidCallback? onChanged;
  final bool showHelp;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDateOfBirthPicker(
      context,
      current: parseDateOfBirth(controller.text.trim()),
      helpText: context.tr('onboarding.dob'),
      entryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        const buttons = Size(64, 48);
        return Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              cancelButtonStyle: TextButton.styleFrom(minimumSize: buttons),
              confirmButtonStyle: TextButton.styleFrom(minimumSize: buttons),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    controller.text = formatDateOfBirth(picked);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final field = FFTextField(
      key: const Key('partner-dob'),
      controller: controller,
      readOnly: true,
      enabled: enabled,
      onTap: enabled ? () => _pick(context) : null,
      label: context.tr('onboarding.dob'),
      hint: context.tr('partnerDob.tapToChoose'),
      helperText: showHelp && errorText == null
          ? context.tr('partnerDob.help')
          : null,
      errorText: errorText,
      validator: (v) {
        final key = partnerDobProblemKey(v, required: required);
        return key == null ? null : context.tr(key);
      },
      suffixIcon: IconButton(
        key: const Key('partner-dob-pick'),
        tooltip: context.tr('member.dobPick'),
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        icon: const Icon(Icons.calendar_today_outlined),
        onPressed: enabled ? () => _pick(context) : null,
      ),
    );
    if (!showHelp) return field;
    // Slice 5: the "why we ask" line is the helper text; this links to the
    // full explanation.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        FFButton(
          key: const Key('partner-dob-why'),
          label: context.tr('partnerDob.whyLink'),
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          maxLines: 3,
          onPressed: () => showPartnerShopExplainer(context, role: role),
        ),
      ],
    );
  }
}

/// Partner DOB slice 5: how a Trainer's or gym owner's date of birth and
/// gender are used in the shop. Draft text pending Tanzanian counsel.
class PartnerShopExplainer extends StatelessWidget {
  const PartnerShopExplainer({
    super.key,
    required this.role,
    this.showTitle = false,
    this.showDraft = true,
  });

  final PartnerRole role;

  /// Shown inside another sheet: a heading of its own.
  final bool showTitle;

  /// The "draft" note (off where the host already shows it).
  final bool showDraft;

  /// The lines for [role], in order (review round 1, 2026-11-10).
  static List<String> linesFor(PartnerRole role) => [
    role == PartnerRole.trainer
        ? 'shop.partnerAbout.askedTrainer'
        : 'shop.partnerAbout.askedOwner',
    'shop.partnerAbout.use',
    if (role == PartnerRole.trainer) 'shop.partnerAbout.useTrainer',
    'shop.partnerAbout.memberDob',
    'shop.partnerAbout.noDob',
    'shop.partnerAbout.under18',
    'shop.partnerAbout.switchOff',
    'shop.partnerAbout.never',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('partner-shop-explainer'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) ...[
          Semantics(
            header: true,
            child: Text(
              context.tr('shop.partnerAbout.title'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
        ],
        for (final key in linesFor(role))
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text('•  ', style: theme.textTheme.bodyMedium),
                ),
                Expanded(
                  child: Text(
                    context.tr(key),
                    key: Key('partner-shop-explainer-$key'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (showDraft)
          Text(
            context.tr('privacy.shop.draft'),
            key: const Key('partner-shop-explainer-draft'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Opens [PartnerShopExplainer] in a sheet of its own.
Future<void> showPartnerShopExplainer(
  BuildContext context, {
  required PartnerRole role,
}) => showFFSheet<void>(
  context,
  title: context.tr('shop.partnerAbout.title'),
  child: PartnerShopExplainer(role: role),
);

/// A gym owner's optional gender: Male, Female, Other or Prefer not to say
/// ([partnerGenderPreferNot], sent as null).
class PartnerGenderField extends StatelessWidget {
  const PartnerGenderField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('partner-gender'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr('partnerGender.optional'),
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final g in partnerGenders)
          DropdownMenuItem(
            value: g,
            child: Text(context.tr('onboarding.gender_$g')),
          ),
        DropdownMenuItem(
          value: partnerGenderPreferNot,
          child: Text(context.tr('partnerGender.preferNot')),
        ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// The gender to send for a [PartnerGenderField] choice.
String? partnerGenderToSend(String choice) =>
    choice == partnerGenderPreferNot ? null : choice;

/// Opens the date of birth and gender sheet. Resolves with the saved
/// details, or null when nothing was saved.
///
/// [canEditGender]: gym owners choose their gender here. A Trainer's gender
/// is their trainer profile's, shown read-only (also for an owner who is a
/// Trainer too, since that is the gender used).
Future<PersonalDetails?> showPartnerDetailsSheet(
  BuildContext context, {
  required PersonalDetails details,
  required bool canEditGender,
  PartnerRole? role,
}) {
  return showFFSheet<PersonalDetails>(
    context,
    title: context.tr('partnerDob.tileTitle'),
    child: PartnerDetailsForm(
      details: details,
      canEditGender: canEditGender,
      role: role,
    ),
  );
}

/// The form inside [showPartnerDetailsSheet]. Sends only what changed.
class PartnerDetailsForm extends StatefulWidget {
  const PartnerDetailsForm({
    super.key,
    required this.details,
    required this.canEditGender,
    PartnerRole? role,
  }) : _role = role;

  final PersonalDetails details;
  final bool canEditGender;
  final PartnerRole? _role;

  /// Whose wording the explanation uses. Without one: gym owners are the
  /// ones who choose their gender here, Trainers are not.
  PartnerRole get role =>
      _role ?? (canEditGender ? PartnerRole.owner : PartnerRole.trainer);

  @override
  State<PartnerDetailsForm> createState() => _PartnerDetailsFormState();
}

class _PartnerDetailsFormState extends State<PartnerDetailsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dob = TextEditingController(
    text: widget.details.dateOfBirth ?? '',
  );
  late final String? _initialGender = widget.details.genderFrom == 'person'
      ? widget.details.gender
      : null;
  late String? _gender = _initialGender;
  bool _busy = false;
  String? _dobError;
  String? _genderError;
  String? _error;

  bool get _genderReadOnly =>
      !widget.canEditGender || widget.details.genderFromTrainerProfile;

  @override
  void dispose() {
    _dob.dispose();
    super.dispose();
  }

  Map<String, dynamic> _changes() {
    final dob = _dob.text.trim();
    return {
      if (dob.isNotEmpty && dob != (widget.details.dateOfBirth ?? ''))
        'dateOfBirth': dob,
      if (!_genderReadOnly && _gender != null && _gender != _initialGender)
        'gender': partnerGenderToSend(_gender!),
    };
  }

  Future<void> _save() async {
    setState(() {
      _dobError = null;
      _genderError = null;
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final changes = _changes();
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final api = AppScope.of(context).api;
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      final saved = await api.savePersonalDetails(changes);
      if (!mounted) return;
      Navigator.of(context).pop(PersonalDetails.fromJson(saved));
    } catch (e) {
      if (!mounted) return;
      final message = partnerDetailsErrorMessage(locale, e);
      setState(() {
        _busy = false;
        if (isPartnerUnder18Error(e) || isDateOfBirthError(e)) {
          _dobError = message;
        } else if (isGenderFieldError(e)) {
          _genderError = message;
        } else {
          _error = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gender = widget.details.gender;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PartnerDobField(
            controller: _dob,
            role: widget.role,
            required: widget.details.required,
            enabled: !_busy,
            errorText: _dobError,
            onChanged: () {
              if (_dobError != null) setState(() => _dobError = null);
            },
          ),
          const SizedBox(height: FFTokens.spacingMd),
          if (_genderReadOnly) ...[
            if (gender != null)
              Semantics(
                key: const Key('partner-gender-readonly'),
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('onboarding.gender'),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    Text(
                      context.tr('onboarding.gender_$gender'),
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (widget.details.genderFromTrainerProfile) ...[
                      const SizedBox(height: FFTokens.spacingXs),
                      Text(
                        context.tr('partnerGender.fromTrainerProfile'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ] else
            PartnerGenderField(
              value: _gender,
              enabled: !_busy,
              errorText: _genderError,
              onChanged: (v) => setState(() {
                _gender = v;
                _genderError = null;
              }),
            ),
          if (_error != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FFAlert(
              key: const Key('partner-details-error'),
              message: _error!,
              tone: FFAlertTone.error,
            ),
          ],
          const SizedBox(height: FFTokens.spacingLg),
          FFButton(
            key: const Key('partner-details-save'),
            label: context.tr('member.save'),
            fullWidth: true,
            loading: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Settings entry "Date of birth and gender" for Trainers and gym owners.
/// Hidden while the feature is off or the details can't be read.
class PartnerDetailsTile extends StatefulWidget {
  const PartnerDetailsTile({super.key, required this.canEditGender});

  final bool canEditGender;

  @override
  State<PartnerDetailsTile> createState() => _PartnerDetailsTileState();
}

class _PartnerDetailsTileState extends State<PartnerDetailsTile> {
  PersonalDetails? _details;
  String? _account;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _account = _accountOf(context);
    if (_account == null) return;
    PartnerDetailsSession.current.addListener(_onSession);
    _load(AppScope.of(context).api);
  }

  @override
  void dispose() {
    PartnerDetailsSession.current.removeListener(_onSession);
    super.dispose();
  }

  /// A save elsewhere (the home card) updates this tile too.
  void _onSession() {
    final details = PartnerDetailsSession.current.value;
    if (details != null && mounted) setState(() => _details = details);
  }

  Future<void> _load(ApiClient api) async {
    final details = await PartnerDetailsSession.load(api, _account!);
    if (mounted) setState(() => _details = details);
  }

  Future<void> _open() async {
    final details = _details;
    if (details == null) return;
    final saved = FFLocaleScope.of(context).t('partnerDob.saved');
    final result = await showPartnerDetailsSheet(
      context,
      details: details,
      canEditGender: widget.canEditGender,
    );
    if (result == null || !mounted) return;
    PartnerDetailsSession.saved(_account!, result);
    setState(() => _details = result);
    FFSnack.success(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    if (_details == null) return const SizedBox.shrink();
    return FFActionTile(
      key: const Key('partner-details-tile'),
      icon: Icons.cake_outlined,
      title: context.tr('partnerDob.tileTitle'),
      subtitle: context.tr('partnerDob.tileSubtitle'),
      onTap: _open,
    );
  }
}

/// Home-screen card "Add your date of birth" for an existing Trainer or gym
/// owner with none: Add opens the sheet, Not now hides it for 30 days, and
/// after 3 dismissals it stops. Never blocks anything.
class PartnerDobPromptCard extends StatefulWidget {
  const PartnerDobPromptCard({
    super.key,
    required this.canEditGender,
    this.now,
  });

  final bool canEditGender;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<PartnerDobPromptCard> createState() => _PartnerDobPromptCardState();
}

class _PartnerDobPromptCardState extends State<PartnerDobPromptCard> {
  PersonalDetails? _details;
  String? _account;
  bool _show = false;
  bool _started = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _account = _accountOf(context);
    if (_account == null) return;
    PartnerDetailsSession.current.addListener(_onSession);
    _load(AppScope.of(context).api);
  }

  @override
  void dispose() {
    PartnerDetailsSession.current.removeListener(_onSession);
    super.dispose();
  }

  /// A save elsewhere (the settings tile) hides the card once nothing is
  /// left to ask.
  void _onSession() {
    final details = PartnerDetailsSession.current.value;
    if (details != null && !details.ask && _show && mounted) {
      setState(() => _show = false);
    }
  }

  Future<void> _load(ApiClient api) async {
    final details = await PartnerDetailsSession.load(api, _account!);
    if (details == null || !details.ask) return;
    if (!await PartnerDobPromptStore.mayShow(_account!, now: _now)) return;
    if (!mounted) return;
    setState(() {
      _details = details;
      _show = true;
    });
  }

  Future<void> _add() async {
    final saved = FFLocaleScope.of(context).t('partnerDob.saved');
    final result = await showPartnerDetailsSheet(
      context,
      details: _details!,
      canEditGender: widget.canEditGender,
    );
    if (result == null || !mounted) return;
    PartnerDetailsSession.saved(_account!, result);
    setState(() {
      _details = result;
      _show = result.ask;
    });
    FFSnack.success(context, saved);
  }

  Future<void> _notNow() async {
    setState(() => _show = false);
    await PartnerDobPromptStore.dismiss(_account!, now: _now);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: FFCard(
        key: const Key('partner-dob-prompt'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cake_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Text(
                    context.tr('partnerDob.promptTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.tr('partnerDob.promptBody')),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingSm,
              children: [
                FFButton(
                  key: const Key('partner-dob-prompt-add'),
                  label: context.tr('partnerDob.add'),
                  visualDensity: VisualDensity.standard,
                  onPressed: _add,
                ),
                FFButton(
                  key: const Key('partner-dob-prompt-dismiss'),
                  label: context.tr('partnerDob.notNow'),
                  variant: FFButtonVariant.ghost,
                  visualDensity: VisualDensity.standard,
                  onPressed: _notNow,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
