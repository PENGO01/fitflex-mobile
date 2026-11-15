import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/date_of_birth.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/media/media_src.dart';
import '../../shared/partner_details.dart';
import '../../shared/widgets/location_picker.dart';
import '../../shared/widgets/partner_details_widgets.dart';
import '../../shared/widgets/persona_switcher.dart';
import '../../shared/widgets/terms_agreement.dart';

class OwnerRegistrationPage extends StatefulWidget {
  const OwnerRegistrationPage({super.key});

  @override
  State<OwnerRegistrationPage> createState() => _OwnerRegistrationPageState();
}

class _OwnerRegistrationPageState extends State<OwnerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _busy = false;

  // Step 0 — Owner info
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Partner date of birth (fitflex-functions#253): asked, with an optional
  // gender, only when GET /me/personal-details says so. Off, failed or
  // already known: the form is as before.
  bool _loadingDetails = true;
  bool _askDob = false;
  final _dobCtrl = TextEditingController();
  String? _dobError;
  String? _gender;
  String? _genderError;

  // Step 1 — Gym list
  final List<_GymDraft> _gyms = [_GymDraft()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDetails();
    });
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
    _phoneCtrl.dispose();
    for (final g in _gyms) {
      g.dispose();
    }
    super.dispose();
  }

  static const int _fullMaxDimension = 1280;
  static const int _fullWebpQuality = 80;
  static const int _thumbMaxDimension = 320;
  static const int _thumbWebpQuality = 70;

  Future<String?> _compressToWebpDataUrl(
    String path, {
    required int maxDimension,
    required int quality,
  }) async {
    try {
      final Uint8List? bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.webp,
      );
      if (bytes == null) return null;
      return 'data:image/webp;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  /// Converts local image paths to WebP data URIs, returning parallel
  /// full-size and thumbnail lists.
  Future<(List<String>, List<String>)> _encodeImages(List<String> paths) async {
    final images = <String>[];
    final thumbnails = <String>[];
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final fullWebp = await _compressToWebpDataUrl(
          path,
          maxDimension: _fullMaxDimension,
          quality: _fullWebpQuality,
        );
        final thumbWebp = await _compressToWebpDataUrl(
          path,
          maxDimension: _thumbMaxDimension,
          quality: _thumbWebpQuality,
        );
        if (fullWebp != null) {
          images.add(fullWebp);
          thumbnails.add(thumbWebp ?? fullWebp);
        } else {
          final bytes = await file.readAsBytes();
          final ext = path.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
          images.add(dataUrl);
          thumbnails.add(dataUrl);
        }
      } catch (_) {
        // Skip unreadable files
      }
    }
    return (images, thumbnails);
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
      // Convert local image paths to base64 data URIs
      final gymPayloads = <Map<String, dynamic>>[];
      for (final g in _gyms) {
        final json = g.toJson();
        if (g.imagePaths.isNotEmpty) {
          final (images, thumbnails) = await _encodeImages(g.imagePaths);
          json['images'] = images;
          json['thumbnails'] = thumbnails;
        }
        gymPayloads.add(json);
      }
      await api.gymOwnerRegister({
        'displayName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        'gyms': gymPayloads,
        if (_askDob) 'dateOfBirth': _dobCtrl.text.trim(),
        if (_askDob && _gender != null) 'gender': partnerGenderToSend(_gender!),
      });
      if (!mounted) return;
      // Re-hydrate auth
      final meRes = await api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      await AppScope.of(
        context,
      ).auth.signIn(AppScope.of(context).auth.token!, user);
      if (!mounted) return;
      context.go(AppRoutes.pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      // partner_under_18 and the date-of-birth/gender refusals say so plainly.
      final message = partnerDetailsErrorMessage(FFLocaleScope.of(context), e);
      // Back to the step with the field the server refused.
      if (_askDob && (isPartnerUnder18Error(e) || isDateOfBirthError(e))) {
        setState(() {
          _step = 0;
          _dobError = message;
        });
      } else if (_askDob && isGenderFieldError(e)) {
        setState(() {
          _step = 0;
          _genderError = message;
        });
      }
      FFSnack.error(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step == 0) {
      final dobProblem = _dobProblem();
      if (dobProblem != null) setState(() => _dobError = dobProblem);
      if (!_formKey.currentState!.validate() || dobProblem != null) return;
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _addGym() {
    setState(() => _gyms.add(_GymDraft()));
  }

  Future<void> _removeGym(int index) async {
    if (_gyms.length <= 1) return;
    final confirmed = await showFFConfirmDialog(
      context,
      title: context.tr('ownerReg.removeGym'),
      message: context.tr('ownerReg.confirmRemoveGym'),
      cancelLabel: context.tr('member.cancel'),
      confirmLabel: context.tr('ownerReg.removeGym'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _gyms[index].dispose();
      _gyms.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ownerReg.title')),
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
                            : context.tr('ownerReg.submit'),
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
        return _ownerInfoStep(context);
      case 1:
        return _gymsStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _ownerInfoStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('ownerReg.ownerTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('ownerReg.ownerSubtitle'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        FFTextField(
          controller: _nameCtrl,
          label: context.tr('ownerReg.displayName'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          label: context.tr('ownerReg.phone'),
          hint: '+255...',
        ),
        if (_askDob) ...[
          const SizedBox(height: FFTokens.spacingSm),
          PartnerDobField(
            key: const Key('owner-reg-dob'),
            controller: _dobCtrl,
            role: PartnerRole.owner,
            errorText: _dobError,
            onChanged: () => setState(() => _dobError = _dobProblem()),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          PartnerGenderField(
            value: _gender,
            errorText: _genderError,
            onChanged: (v) => setState(() {
              _gender = v;
              _genderError = null;
            }),
          ),
        ],
      ],
    );
  }

  Widget _gymsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('ownerReg.gymTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('ownerReg.gymSubtitle'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        ..._gyms.asMap().entries.map((entry) {
          final i = entry.key;
          final g = entry.value;
          return _GymCardWidget(
            gym: g,
            index: i,
            canRemove: _gyms.length > 1,
            onRemove: () => _removeGym(i),
            onChanged: () => setState(() {}),
          );
        }),
        const SizedBox(height: 12),
        FFButton(
          label: context.tr('ownerReg.addGym'),
          onPressed: _addGym,
          variant: FFButtonVariant.secondary,
          icon: Icons.add,
        ),
        const SizedBox(height: 16),
        TermsAgreementField(key: _termsKey),
      ],
    );
  }
}

/// Gym card widget — extracted as its own stateful widget for map/images state
class _GymCardWidget extends StatefulWidget {
  final _GymDraft gym;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _GymCardWidget({
    required this.gym,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_GymCardWidget> createState() => _GymCardWidgetState();
}

class _GymCardWidgetState extends State<_GymCardWidget> {
  final ImagePicker _picker = ImagePicker();

  /// Room left under the server's cap (kGymMaxPhotos, too_many_images).
  int get _photoRoom => kGymMaxPhotos - widget.gym.imagePaths.length;

  Future<void> _pickImage() async {
    if (_photoRoom <= 0) return _sayPhotoMax();
    final picked = await _picker.pickMultiImage(
      maxWidth: 1024,
      imageQuality: 80,
      limit: _photoRoom > 1 ? _photoRoom : null,
    );
    if (!mounted || picked.isEmpty) return;
    final files = picked.take(_photoRoom).toList();
    setState(() {
      widget.gym.imagePaths.addAll(files.map((file) => file.path));
    });
    widget.onChanged();
    if (picked.length > files.length) _sayPhotoMax();
  }

  void _sayPhotoMax() => FFSnack.info(
    context,
    context.tr('photos.max').replaceAll('{n}', '$kGymMaxPhotos'),
  );

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.tr('ownerReg.gym')} ${widget.index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: context.tr('common.close'),
                    icon: const Icon(Icons.close, size: FFTokens.iconMd),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Name
            FFTextField(
              controller: gym.nameCtrl,
              label: context.tr('ownerReg.gymName'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Location (text)
            FFTextField(
              controller: gym.locationCtrl,
              label: context.tr('ownerReg.gymLocation'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Rates
            FFTextField(
              controller: gym.rateDayCtrl,
              keyboardType: TextInputType.number,
              label: context.tr('ownerReg.ratePerDay'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              controller: gym.rateWeekCtrl,
              keyboardType: TextInputType.number,
              label: context.tr('ownerReg.ratePerWeek'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              controller: gym.rateMonthCtrl,
              keyboardType: TextInputType.number,
              label: context.tr('ownerReg.ratePerMonth'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.tr('onboarding.required')
                  : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),

            // Trainers join through their own join request, which the owner
            // approves once the gym exists; a new gym has no one to pick yet.
            FFFieldLabel(context.tr('ownerReg.trainersLabel')),
            Text(
              context.tr('ownerReg.trainersJoinHint'),
              key: const Key('owner-reg-trainers-join-hint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Map picker
            FFFieldLabel(context.tr('ownerReg.mapLabel')),
            LocationPicker(
              initialLat: gym.lat,
              initialLng: gym.lng,
              height: 200,
              onChanged: (latlng) {
                gym.lat = latlng.latitude;
                gym.lng = latlng.longitude;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 16),

            // Image picker
            FFFieldLabel(context.tr('ownerReg.imagesLabel')),
            Text(
              context.tr('ownerReg.imagesHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            if (gym.imagePaths.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: gym.imagePaths.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusMd,
                          ),
                          child: Image.file(
                            File(gym.imagePaths[i]),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                gym.imagePaths.removeAt(i);
                              });
                              widget.onChanged();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            FFButton(
              label: context.tr('ownerReg.pickImage'),
              onPressed: _photoRoom > 0 ? _pickImage : null,
              variant: FFButtonVariant.secondary,
              icon: Icons.add_a_photo,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Gym Draft Model ───

class _GymDraft {
  final nameCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final rateDayCtrl = TextEditingController();
  final rateWeekCtrl = TextEditingController();
  final rateMonthCtrl = TextEditingController();
  String tier = 'standard';
  double? lat;
  double? lng;
  List<String> imagePaths = [];

  Map<String, dynamic> toJson() => {
    'name': nameCtrl.text.trim(),
    'location': locationCtrl.text.trim(),
    'tier': tier,
    'ratePerDay': num.tryParse(rateDayCtrl.text) ?? 0,
    'ratePerWeek': num.tryParse(rateWeekCtrl.text) ?? 0,
    'ratePerMonth': num.tryParse(rateMonthCtrl.text) ?? 0,
    'perVisitRate': num.tryParse(rateDayCtrl.text) ?? 0,
    'venueType': 'physical',
    'status': 'active',
    'accessMode': 'paid_visit',
    if (lat != null && lng != null) 'coordinates': {'lat': lat, 'lng': lng},
    // images are encoded by _submit() and set separately
  };

  void dispose() {
    nameCtrl.dispose();
    locationCtrl.dispose();
    rateDayCtrl.dispose();
    rateWeekCtrl.dispose();
    rateMonthCtrl.dispose();
  }
}
