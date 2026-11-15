import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/date_of_birth.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/partner_details.dart';
import '../../shared/widgets/partner_details_widgets.dart';
import '../../shared/widgets/persona_switcher.dart';
import '../../shared/widgets/ff_photo_picker_field.dart';
import '../../shared/widgets/social_links.dart';
import '../../shared/widgets/terms_agreement.dart';
import '../../shared/widgets/trainer_form_page.dart';
import '../../shared/components/components.dart';

class TrainerRegistrationPage extends StatefulWidget {
  const TrainerRegistrationPage({super.key});

  @override
  State<TrainerRegistrationPage> createState() =>
      _TrainerRegistrationPageState();
}

class _TrainerRegistrationPageState extends State<TrainerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _busy = false;

  // Step 0 — Personal
  final _nameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  String? _photoUrl;
  String? _gender;
  final _bioCtrl = TextEditingController();

  // Partner date of birth (fitflex-functions#253): asked only when
  // GET /me/personal-details says so. Off, failed or already known: the
  // form is as before. The gender above is the one used (no second
  // question).
  bool _loadingDetails = true;
  bool _askDob = false;
  final _dobCtrl = TextEditingController();
  String? _dobError;

  // Step 1 — Professional
  final _sessionRateCtrl = TextEditingController();
  final List<String> _specialties = [];
  final _socials = SocialHandleFields.controllersFor(const SocialLinks());

  static const _specialtyOptions = [
    'weight_training',
    'cardio',
    'yoga',
    'boxing',
    'pilates',
    'crossfit',
    'swimming',
    'nutrition',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetails());
  }

  Future<void> _loadDetails() async {
    final details = await loadPersonalDetails(AppScope.of(context).api);
    if (!mounted) return;
    setState(() {
      _askDob = details?.ask == true;
      _loadingDetails = false;
    });
  }

  /// The date of birth is required and 18+ when asked; else null.
  String? _dobProblem() {
    if (!_askDob) return null;
    final key = partnerDobProblemKey(_dobCtrl.text);
    return key == null ? null : context.tr(key);
  }

  @override
  void dispose() {
    _dobCtrl.dispose();
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    _sessionRateCtrl.dispose();
    for (final c in _socials.values) {
      c.dispose();
    }
    super.dispose();
  }

  final _termsKey = GlobalKey<TermsAgreementFieldState>();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final dobProblem = _dobProblem();
    if (dobProblem != null) {
      setState(() {
        _step = 0;
        _dobError = dobProblem;
      });
      return;
    }
    // Terms: the role's terms must be agreed to, and put on record, first.
    final terms = _termsKey.currentState;
    if (terms == null || !terms.agreed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('terms.mustAgree'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      if (!await terms.record()) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('terms.loadFailed'))));
        return;
      }
      if (!mounted) return;
      await api.trainerRegister({
        'displayName': _nameCtrl.text.trim(),
        if (_nicknameCtrl.text.trim().isNotEmpty)
          'nickname': _nicknameCtrl.text.trim(),
        'photoUrl': _photoUrl ?? '',
        'gender': _gender,
        'bio': _bioCtrl.text.trim(),
        'hourlyRateTzs': num.tryParse(_sessionRateCtrl.text) ?? 0,
        'specialties': _specialties,
        'socialLinks': SocialHandleFields.valuesOf(_socials),
        if (_askDob) 'dateOfBirth': _dobCtrl.text.trim(),
      });
      if (!mounted) return;
      // Re-hydrate auth to reflect onboarding completion
      final meRes = await api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      await AppScope.of(
        context,
      ).auth.signIn(AppScope.of(context).auth.token!, user);
      if (!mounted) return;
      // Active at once: straight on to where this role lands now.
      context.go(routeForSignedInUser(AppScope.of(context).auth));
    } on ApiException catch (e) {
      if (!mounted) return;
      // partner_under_18 and the date-of-birth refusal say so plainly.
      final message = partnerDetailsErrorMessage(FFLocaleScope.of(context), e);
      if (_askDob && (isPartnerUnder18Error(e) || isDateOfBirthError(e))) {
        setState(() {
          _step = 0;
          _dobError = message;
        });
      }
      FFSnack.error(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step < 1) {
      final dobProblem = _dobProblem();
      if (dobProblem != null) {
        setState(() => _dobError = dobProblem);
        return;
      }
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('trainerReg.title')),
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              _back();
            } else {
              context.go(AppRoutes.role);
            }
          },
        ),
        actions: const [PersonaSwitchButton(), AppPrefsButtons()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Step indicator
                Row(
                  children: List.generate(2, (i) {
                    final active = i <= _step;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _loadingDetails
                      ? const Center(child: FFSpinner())
                      : SingleChildScrollView(child: _buildStep(context)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: FFButton(
                          label: context.tr('onboarding.back'),
                          onPressed: _back,
                          variant: FFButtonVariant.secondary,
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      child: FFButton(
                        label: _step < 1
                            ? context.tr('onboarding.next')
                            : context.tr('trainerReg.submit'),
                        onPressed: _busy || _loadingDetails ? null : _next,
                        loading: _busy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _personalStep(context);
      case 1:
        return _professionalStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _personalStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('trainerReg.personalTitle'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('trainerReg.personalSubtitle'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FFTextField(
          controller: _nameCtrl,
          label: context.tr('trainerReg.displayName'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('trainer-reg-nickname'),
          controller: _nicknameCtrl,
          decoration: InputDecoration(
            labelText: context.tr('trainer.nickname'),
            hintText: context.tr('trainer.nicknameHint'),
            helperText: context.tr('trainer.nicknameHelp'),
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => trainerNicknameError(context, v),
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('trainerReg.picture'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Center(
          child: FFPhotoPickerField(
            profilePhoto: true,
            value: _photoUrl,
            onChanged: (url) => setState(() => _photoUrl = url),
            size: 100,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: InputDecoration(
            labelText: context.tr('trainerReg.gender'),
            border: const OutlineInputBorder(),
          ),
          items: ['male', 'female', 'other']
              .map(
                (g) => DropdownMenuItem(
                  value: g,
                  child: Text(context.tr('onboarding.gender_$g')),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _gender = v),
          validator: (v) =>
              v == null ? context.tr('onboarding.required') : null,
        ),
        if (_askDob) ...[
          const SizedBox(height: 16),
          PartnerDobField(
            key: const Key('trainer-reg-dob'),
            controller: _dobCtrl,
            role: PartnerRole.trainer,
            errorText: _dobError,
            onChanged: () => setState(() => _dobError = _dobProblem()),
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.tr('trainerReg.bio'),
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
      ],
    );
  }

  Widget _professionalStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('trainerReg.professionalTitle'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('trainerReg.professionalSubtitle'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FFTextField(
          controller: _sessionRateCtrl,
          label: context.tr('trainerReg.sessionRate'),
          suffixText:
              '${currencyLabel('TZS')}${context.tr('trainerReg.perSession')}',
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('trainerReg.specialties'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _specialtyOptions.map((s) {
            final selected = _specialties.contains(s);
            return FilterChip(
              label: Text(context.tr('trainerReg.specialty_$s')),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _specialties.add(s);
                  } else {
                    _specialties.remove(s);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Text(
          context.tr('social.title'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('social.optionalHint'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SocialHandleFields(controllers: _socials),
        const SizedBox(height: 12),
        TermsAgreementField(key: _termsKey),
      ],
    );
  }
}
