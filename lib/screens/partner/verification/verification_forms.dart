// Partner verification forms: identity, business details, one document (its
// details and file), and payout accounts. Each form saves to the API and
// returns the refreshed overview to the verification centre.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/product_categories.dart';
import '../../../shared/tanzania_banks.dart';
import '../../../shared/tanzania_regions.dart';
import '../../../shared/widgets/product_category_picker.dart';
import 'verification_models.dart';
import 'verification_repository.dart';

const _maxFileBytes = 10 * 1024 * 1024;

String _errorText(BuildContext context, Object e) {
  if (e is ApiException) {
    final key = switch (e.code) {
      'case_locked' => 'kyc.locked',
      'file_too_large' => 'kyc.error.fileTooLarge',
      'unsupported_file_type' => 'kyc.error.fileType',
      'encrypted_pdf' => 'kyc.error.encryptedPdf',
      'pdf_with_active_content' => 'kyc.error.pdfContent',
      'unreadable_image' => 'kyc.error.unreadableImage',
      'storage_service_unavailable' ||
      'storage_upload_failed' => 'kyc.error.storage',
      'account_already_added' => 'kyc.error.accountExists',
      'too_many_accounts' => 'kyc.error.tooManyAccounts',
      'invalid_mobile_number' => 'kyc.error.mobileNumber',
      'expiresOn_before_issuedOn' => 'kyc.error.dates',
      'invalid_email' => 'kyc.error.email',
      _ => null,
    };
    if (key != null) return context.tr(key);
  }
  return errorMessage(FFLocaleScope.of(context), e);
}

// Replace any message still showing rather than queueing behind it.
void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

String? _blankToNull(String v) => v.trim().isEmpty ? null : v.trim();

/// A form page scaffold with a save button that shows progress.
class _FormScaffold extends StatelessWidget {
  const _FormScaffold({
    required this.title,
    required this.formKey,
    required this.busy,
    required this.onSave,
    required this.children,
  });
  final String title;
  final GlobalKey<FormState> formKey;
  final bool busy;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: children,
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(FFTokens.spacingLg),
      child: FFButton(
        key: const Key('kyc-form-save'),
        label: context.tr('kyc.save'),
        onPressed: busy ? null : onSave,
        loading: busy,
      ),
    ),
  );
}

Widget _gap() => const SizedBox(height: FFTokens.spacingMd);

Widget _text(
  BuildContext context,
  String key,
  TextEditingController c, {
  bool required = false,
  TextInputType? keyboard,
  String? hintKey,
  String? Function(String)? check,
}) => Padding(
  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
  child: FFTextField(
    key: Key('kyc-field-$key'),
    controller: c,
    label: context.tr('kyc.field.$key') + (required ? ' *' : ''),
    helperText: hintKey == null ? null : context.tr(hintKey),
    validator: (v) {
      final value = v ?? '';
      if (required && value.trim().isEmpty) return context.tr('kyc.required');
      return check?.call(value);
    },
    keyboardType: keyboard,
  ),
);

Widget _choice(
  BuildContext context,
  String key,
  String? value,
  List<String> options,
  ValueChanged<String?> onChanged, {
  bool required = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
  child: DropdownButtonFormField<String>(
    key: Key('kyc-field-$key'),
    initialValue: options.contains(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: context.tr('kyc.field.$key') + (required ? ' *' : ''),
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final o in options)
        DropdownMenuItem(value: o, child: Text(context.tr('kyc.option.$o'))),
    ],
    onChanged: onChanged,
    validator: (v) => required && v == null ? context.tr('kyc.required') : null,
  ),
);

/// A YYYY-MM-DD date field with a date picker.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.optionalHint = false,
  });
  final String fieldKey;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;
  final bool optionalHint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
    child: FormField<String>(
      initialValue: value,
      validator: (v) => required && (v == null || v.isEmpty)
          ? context.tr('kyc.required')
          : null,
      builder: (state) => InkWell(
        key: Key('kyc-field-$fieldKey'),
        onTap: () async {
          final now = DateTime.now();
          final initial = DateTime.tryParse(state.value ?? '') ?? now;
          final picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(now.year - 80),
            lastDate: DateTime(now.year + 30),
          );
          if (picked == null) return;
          final day = picked.toIso8601String().substring(0, 10);
          state.didChange(day);
          onChanged(day);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText:
                context.tr('kyc.field.$fieldKey') +
                (required ? ' *' : '') +
                (optionalHint
                    ? ' ${context.tr('kyc.field.optionalSuffix')}'
                    : ''),
            border: const OutlineInputBorder(),
            errorText: state.errorText,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(state.value ?? ''),
        ),
      ),
    ),
  );
}

class _AddressFields {
  _AddressFields(KycAddress a)
    : line1 = TextEditingController(text: a.line1),
      // An address is a street or plot and a city, picked from the regions
      // of Tanzania. One saved with only a region shows that region.
      city = TextEditingController(
        text: (a.city ?? '').isNotEmpty ? a.city : a.region,
      );
  final TextEditingController line1;
  final TextEditingController city;

  List<Widget> build(
    BuildContext context,
    String prefix, {
    bool required = true,
  }) => [
    _text(context, '${prefix}Line1', line1, required: required),
    _CityPicker(
      fieldKey: '${prefix}City',
      controller: city,
      required: required,
    ),
  ];

  Map<String, dynamic> toJson() => {
    'line1': line1.text.trim(),
    'city': city.text.trim(),
    'country': 'TZ',
  };

  void dispose() {
    line1.dispose();
    city.dispose();
  }
}

/// City or town as a list to pick from (the regions of Tanzania), kept in
/// [controller] so the form saves it like any other field. A value typed
/// before the list existed stays selectable until it is changed.
class _CityPicker extends StatefulWidget {
  const _CityPicker({
    required this.fieldKey,
    required this.controller,
    this.required = false,
  });

  final String fieldKey;
  final TextEditingController controller;
  final bool required;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  late final String _typed = widget.controller.text.trim();
  late String? _value =
      matchTanzaniaRegion(_typed) ?? (_typed.isEmpty ? null : _typed);

  @override
  void initState() {
    super.initState();
    // Normalise "dar es salaam" → "Dar es Salaam" on the way in.
    if (_value != null) widget.controller.text = _value!;
  }

  @override
  Widget build(BuildContext context) {
    final legacy = _typed.isNotEmpty && matchTanzaniaRegion(_typed) == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: DropdownButtonFormField<String>(
        key: Key('kyc-field-${widget.fieldKey}'),
        initialValue: _value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText:
              context.tr('kyc.field.${widget.fieldKey}') +
              (widget.required ? ' *' : ''),
          border: const OutlineInputBorder(),
        ),
        hint: Text(context.tr('kyc.field.cityChoose')),
        items: [
          if (legacy) DropdownMenuItem(value: _typed, child: Text(_typed)),
          for (final r in tanzaniaRegions)
            DropdownMenuItem(value: r, child: Text(r)),
        ],
        onChanged: (v) => setState(() {
          _value = v;
          widget.controller.text = v ?? '';
        }),
        validator: (v) => widget.required && (v == null || v.isEmpty)
            ? context.tr('kyc.required')
            : null,
      ),
    );
  }
}

String? _checkEmail(BuildContext context, String v) =>
    v.trim().isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
    ? null
    : context.tr('kyc.error.email');

// ── Identity ────────────────────────────────────────────────────────────────

class PersonFormPage extends StatefulWidget {
  const PersonFormPage({
    super.key,
    required this.repository,
    required this.overview,
  });
  final VerificationRepository repository;
  final KycOverview overview;

  @override
  State<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends State<PersonFormPage> {
  final _form = GlobalKey<FormState>();
  late final String _role = personRoleFor(widget.overview.partnerType);
  late final List<String> _fields = personFieldsFor(
    widget.overview.partnerType,
  );
  late final KycPerson _p =
      widget.overview.personFor(_role) ?? KycPerson(role: _role);
  // A vendor's own details start from their account (name, and nationality
  // and ID number when the profile has them); nothing is guessed otherwise.
  late final Map<String, dynamic>? _account = context
      .getInheritedWidgetOfExactType<AppScope>()
      ?.auth
      .user;
  String? _accountText(String key) {
    final v = _account?[key]?.toString().trim();
    return v == null || v.isEmpty ? null : v;
  }

  late final _name = TextEditingController(
    text: _p.fullName ?? (_isVendor ? _accountText('displayName') : null),
  );
  late final _idNumber = TextEditingController(
    text: _p.idNumber ?? (_isVendor ? _accountText('idNumber') : null),
  );
  late final _phone = TextEditingController(text: _p.phone);
  late final _email = TextEditingController(text: _p.email);
  late final _position = TextEditingController(text: _p.position);
  late final _address = _AddressFields(_p.address);
  late String? _nationality =
      _p.nationality ??
      (_isVendor
          ? (countries.containsKey(_accountText('nationality'))
                ? _accountText('nationality')
                : null)
          : 'TZ');
  late String? _idType = _p.idType ?? 'nida';
  late String? _relationship = _p.relationship;
  late String? _vendorPosition = vendorPositions.contains(_p.position)
      ? _p.position
      : null;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _idNumber, _phone, _email, _position]) {
      c.dispose();
    }
    _address.dispose();
    super.dispose();
  }

  bool get _isTrainer => widget.overview.partnerType == 'trainer';
  bool get _isVendor => widget.overview.partnerType == 'vendor';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'fullName': _name.text.trim(),
        'nationality': _nationality ?? 'TZ',
        'idType': _idType,
        'idNumber': _blankToNull(_idNumber.text),
        if (_fields.contains('phone')) 'phone': _blankToNull(_phone.text),
        if (_fields.contains('email')) 'email': _blankToNull(_email.text),
        if (_fields.contains('address')) 'address': _address.toJson(),
        if (_fields.contains('position'))
          'position': _isVendor
              ? _vendorPosition
              : _blankToNull(_position.text),
        if (_fields.contains('relationship')) 'relationship': _relationship,
      };
      final updated = await widget.repository.updatePerson(_role, body);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = widget.overview.partnerType == 'vendor';
    // Tanzanian trainers identify with NIDA; everyone else may use a passport.
    final idTypes = _isTrainer
        ? ((_nationality ?? 'TZ') == 'TZ' ? const ['nida'] : const ['passport'])
        : const ['nida', 'passport'];
    if (!idTypes.contains(_idType)) _idType = idTypes.first;
    return _FormScaffold(
      title: context.tr(vendor ? 'kyc.form.yourDetails' : 'kyc.form.identity'),
      formKey: _form,
      busy: _busy,
      onSave: _save,
      children: [
        Text(
          context.tr(
            vendor ? 'kyc.form.yourDetailsIntro' : 'kyc.form.identityIntro',
          ),
        ),
        _gap(),
        _text(context, 'fullName', _name, required: true),
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: DropdownButtonFormField<String>(
            key: const Key('kyc-field-nationality'),
            initialValue: countries.containsKey(_nationality)
                ? _nationality
                : (vendor ? null : 'TZ'),
            isExpanded: true,
            decoration: InputDecoration(
              labelText:
                  context.tr('kyc.field.nationality') + (vendor ? ' *' : ''),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final e in countries.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(context.tr('kyc.country.${e.key}')),
                ),
            ],
            validator: (v) =>
                vendor && v == null ? context.tr('kyc.required') : null,
            onChanged: (v) =>
                setState(() => _nationality = v ?? (vendor ? null : 'TZ')),
          ),
        ),
        _choice(
          context,
          'idType',
          _idType,
          idTypes,
          (v) => setState(() => _idType = v),
          required: true,
        ),
        _text(
          context,
          'idNumber',
          _idNumber,
          required: true,
          hintKey: _idType == 'nida' ? 'kyc.hint.nida' : null,
        ),
        if (_fields.contains('position'))
          vendor
              ? _choice(
                  context,
                  'position',
                  _vendorPosition,
                  vendorPositions,
                  (v) => setState(() => _vendorPosition = v),
                  required: true,
                )
              : _text(context, 'position', _position),
        if (_fields.contains('relationship'))
          _choice(
            context,
            'relationship',
            _relationship,
            relationships,
            (v) => setState(() => _relationship = v),
            required: true,
          ),
        if (_fields.contains('phone'))
          _text(
            context,
            'phone',
            _phone,
            required: !vendor,
            keyboard: TextInputType.phone,
          ),
        if (_fields.contains('email'))
          _text(
            context,
            'email',
            _email,
            required: !vendor,
            keyboard: TextInputType.emailAddress,
            check: (v) => _checkEmail(context, v),
          ),
        if (_fields.contains('address')) ...[
          FFSectionTitle(context.tr('kyc.field.address')),
          ..._address.build(context, 'address'),
        ],
      ],
    );
  }
}

// ── Business ────────────────────────────────────────────────────────────────

class BusinessFormPage extends StatefulWidget {
  const BusinessFormPage({
    super.key,
    required this.repository,
    required this.overview,
  });
  final VerificationRepository repository;
  final KycOverview overview;

  @override
  State<BusinessFormPage> createState() => _BusinessFormPageState();
}

class _BusinessFormPageState extends State<BusinessFormPage> {
  final _form = GlobalKey<FormState>();
  late final KycCaseInfo? _c = widget.overview.kycCase;
  late final _legalName = TextEditingController(text: _c?.legalName);
  late final _tradingName = TextEditingController(text: _c?.tradingName);
  late final _registration = TextEditingController(
    text: _c?.registrationNumber,
  );
  late final _tin = TextEditingController(text: _c?.tin);
  late final _address = _AddressFields(
    _c?.registeredAddress ?? const KycAddress(),
  );
  late String? _entityType = _c?.entityType;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_legalName, _tradingName, _registration, _tin]) {
      c.dispose();
    }
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.updateBusiness({
        'legalName': _legalName.text.trim(),
        'tradingName': _tradingName.text.trim(),
        'entityType': _entityType,
        'registrationNumber': _registration.text.trim(),
        'registrationAuthority': 'BRELA',
        'tin': _tin.text.trim(),
        'registeredAddress': _address.toJson(),
      });
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Vendors only have to give the TIN; the rest is collected if they have it.
  bool get _strict => widget.overview.partnerType != 'vendor';

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: context.tr('kyc.form.business'),
    formKey: _form,
    busy: _busy,
    onSave: _save,
    children: [
      Text(context.tr('kyc.form.businessIntro')),
      _gap(),
      _text(context, 'legalName', _legalName, required: _strict),
      _text(context, 'tradingName', _tradingName, required: _strict),
      _choice(
        context,
        'entityType',
        _entityType,
        entityTypes,
        (v) => setState(() => _entityType = v),
        required: _strict,
      ),
      _text(
        context,
        'registrationNumber',
        _registration,
        required: _strict,
        hintKey: 'kyc.hint.brela',
      ),
      _text(
        context,
        'tin',
        _tin,
        required: true,
        keyboard: TextInputType.number,
      ),
      FFSectionTitle(context.tr('kyc.field.registeredAddress')),
      ..._address.build(context, 'address', required: _strict),
    ],
  );
}

// ── Vendor business profile ────────────────────────────────────────────────

/// The two checklist items a vendor keeps on their business profile: how to
/// contact them (a number; the email is optional) and the product categories
/// they sell in. Saved as a draft — never published — so it works while the
/// vendor is still pending approval.
class VendorKycProfilePage extends StatefulWidget {
  const VendorKycProfilePage({super.key, required this.api});
  final ApiClient api;

  @override
  State<VendorKycProfilePage> createState() => _VendorKycProfilePageState();
}

class _VendorKycProfilePageState extends State<VendorKycProfilePage> {
  final _form = GlobalKey<FormState>();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  List<String> _categories = const [];
  bool _categoriesTried = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _contact.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    try {
      await ProductCategories.load(widget.api);
      final p = await widget.api.vendorProfile();
      _contact.text = p['contactNumber']?.toString() ?? '';
      _email.text = p['email']?.toString() ?? '';
      final stored = p['productCategories'];
      // Older values map onto the list when they match a key or its name.
      _categories = ProductCategories.keysFor([
        if (stored is List) ...stored,
        if (stored is! List || stored.isEmpty) p['businessCategory'],
      ]);
    } catch (_) {
      // Start empty; saving will report any real problem.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _categoriesTried = true);
    final valid = _form.currentState!.validate();
    if (!valid || _categories.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.vendorSaveProfile({
        'contactNumber': _contact.text.trim(),
        'email': _email.text.trim(),
        'productCategories': _categories,
      });
      if (!mounted) return;
      _snack(context, context.tr('kyc.vendorProfile.saved'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      if (mounted) _snack(context, _errorText(context, e));
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    String? Function(String)? check,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
    child: FFTextField(
      key: Key('kyc-vendor-$key'),
      controller: c,
      label: label,
      validator: check == null ? null : (v) => check(v ?? ''),
      keyboardType: keyboard,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return _FormScaffold(
      title: context.tr('kyc.vendorProfile.title'),
      formKey: _form,
      busy: _busy || _loading,
      onSave: _save,
      children: _loading
          ? [const Center(child: FFSpinner(size: 32))]
          : [
              Text(context.tr('kyc.vendorProfile.hint')),
              _gap(),
              _field(
                'contactNumber',
                '${context.tr('vendor.contactNumber')} *',
                _contact,
                keyboard: TextInputType.phone,
                check: (v) =>
                    v.trim().isEmpty ? context.tr('kyc.required') : null,
              ),
              _field(
                'email',
                context.tr('vendor.emailOptional'),
                _email,
                keyboard: TextInputType.emailAddress,
                // Optional: only checked when something is given.
                check: (v) => _checkEmail(context, v),
              ),
              ProductCategoryMultiSelect(
                keyPrefix: 'kyc-vendor-category',
                required: true,
                showError: _categoriesTried,
                selected: _categories,
                onChanged: (next) => setState(() => _categories = next),
              ),
            ],
    );
  }
}

// ── Documents ───────────────────────────────────────────────────────────────

enum DocumentSource { camera, gallery, file }

class PickedDocument {
  const PickedDocument(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

typedef PickDocument = Future<PickedDocument?> Function(DocumentSource source);

/// The device's camera, gallery or file picker.
Future<PickedDocument?> pickDocumentFromDevice(DocumentSource source) async {
  if (source == DocumentSource.file) {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    return PickedDocument(await file.readAsBytes(), file.name);
  }
  final image = await ImagePicker().pickImage(
    source: source == DocumentSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 85,
  );
  if (image == null) return null;
  return PickedDocument(await image.readAsBytes(), image.name);
}

class DocumentPage extends StatefulWidget {
  const DocumentPage({
    super.key,
    required this.repository,
    required this.overview,
    required this.requirementKey,
    required this.pickDocument,
  });
  final VerificationRepository repository;
  final KycOverview overview;
  final String requirementKey;
  final PickDocument pickDocument;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  final _form = GlobalKey<FormState>();
  late KycOverview _overview = widget.overview;
  late final DocumentSpec _spec =
      documentSpecs[widget.requirementKey] ?? const DocumentSpec(['other'], []);
  late final KycDocument? _doc = widget.overview.currentDocument(
    widget.requirementKey,
  );
  // A reviewed document starts over: its details aren't carried into the new one.
  late final bool _fresh = _doc == null || _doc.status != 'pending';
  // The ID, registration and TIN numbers are shared with the identity and
  // business forms: the server fills whichever was not given first.
  late final String? _shared = _sharedNumber();
  late final String? _ownNumber = _fresh ? null : _doc?.documentNumber;
  late final bool _prefilled =
      (_ownNumber ?? '').trim().isEmpty && _shared != null;
  late final _number = TextEditingController(
    text: (_ownNumber ?? '').trim().isEmpty ? _shared : _ownNumber,
  );
  late final _issuer = TextEditingController(
    text: _fresh ? null : _doc?.issuer,
  );
  late String? _issuedOn = _fresh ? null : _doc?.issuedOn;
  late String? _expiresOn = _fresh ? null : _doc?.expiresOn;
  late String _docType = (_doc != null && _spec.types.contains(_doc.docType))
      ? _doc.docType
      : _spec.types.first;
  bool _busy = false;
  // The picture just uploaded, shown at once without fetching it again.
  Uint8List? _uploadedBytes;
  // Previews fetched through the repository, by document id.
  final _previews = <String, Future<Uint8List>>{};

  @override
  void dispose() {
    _number.dispose();
    _issuer.dispose();
    super.dispose();
  }

  String? _sharedNumber() {
    final o = widget.overview;
    final value = switch (widget.requirementKey) {
      'owner_id' || 'trainer_id' || 'representative_id' =>
        o.personFor(personRoleFor(o.partnerType))?.idNumber,
      'business_registration' => o.kycCase?.registrationNumber,
      'tin_certificate' => o.kycCase?.tin,
      _ => null,
    };
    return (value ?? '').trim().isEmpty ? null : value!.trim();
  }

  KycDocument? get _current => _overview.currentDocument(widget.requirementKey);

  Future<void> _upload(DocumentSource source) async {
    final picked = await widget.pickDocument(source);
    if (picked == null || !mounted) return;
    if (picked.bytes.length > _maxFileBytes) {
      return _snack(context, context.tr('kyc.error.fileTooLarge'));
    }
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.uploadDocumentFile(
        widget.requirementKey,
        bytes: picked.bytes,
        filename: picked.name,
        docType: _docType,
      );
      if (!mounted) return;
      setState(() {
        _overview = updated;
        _uploadedBytes = _looksLikeImage(picked.name) ? picked.bytes : null;
      });
      _snack(context, context.tr('kyc.doc.uploaded'));
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_spec.fields.contains('expiresOn') &&
        _issuedOn != null &&
        _expiresOn != null &&
        _expiresOn!.compareTo(_issuedOn!) <= 0) {
      return _snack(context, context.tr('kyc.error.dates'));
    }
    setState(() => _busy = true);
    try {
      final updated = await widget.repository
          .updateDocument(widget.requirementKey, {
            'docType': _docType,
            if (_spec.fields.contains('documentNumber'))
              'documentNumber': _blankToNull(_number.text),
            if (_spec.fields.contains('issuer'))
              'issuer': _blankToNull(_issuer.text),
            if (_spec.fields.contains('issuedOn')) 'issuedOn': _issuedOn,
            if (_spec.fields.contains('expiresOn')) 'expiresOn': _expiresOn,
          });
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final hasFile =
        current != null && current.status == 'pending' && current.hasFile;
    final rejected = current != null && current.status == 'rejected';
    return _FormScaffold(
      title: context.tr('kyc.item.${_titleKey(widget.requirementKey)}'),
      formKey: _form,
      busy: _busy,
      onSave: _save,
      children: [
        if (rejected)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
            child: FFAlert(
              message: [
                context.tr('kyc.doc.rejected'),
                if (current.reviewNote != null) current.reviewNote!,
              ].join('\n\n'),
              tone: FFAlertTone.error,
            ),
          ),
        Text(context.tr('kyc.doc.intro.${widget.requirementKey}')),
        _gap(),
        if (_spec.types.length > 1)
          _choice(
            context,
            'docType',
            _docType,
            _spec.types,
            (v) => setState(() => _docType = v ?? _docType),
            required: true,
          ),
        if (_spec.fields.contains('issuer'))
          _text(
            context,
            _issuerLabel(widget.requirementKey),
            _issuer,
            required: true,
          ),
        if (_spec.fields.contains('documentNumber'))
          _text(
            context,
            _numberLabel(widget.requirementKey),
            _number,
            required: _shared == null,
            hintKey: _prefilled ? 'kyc.doc.numberShared' : null,
          ),
        if (_spec.fields.contains('issuedOn'))
          _DateField(
            fieldKey: 'issuedOn',
            value: _issuedOn,
            required: true,
            onChanged: (v) => setState(() => _issuedOn = v),
          ),
        if (_spec.fields.contains('expiresOn'))
          _DateField(
            fieldKey: 'expiresOn',
            value: _expiresOn,
            required: false,
            optionalHint: true,
            onChanged: (v) => setState(() => _expiresOn = v),
          ),
        FFSectionTitle(context.tr('kyc.doc.file')),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (hasFile)
                    _filePreview(current)
                  else
                    const Icon(Icons.upload_file_outlined),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Text(
                      !hasFile
                          ? context.tr('kyc.doc.noFile')
                          : (current.isImage || _uploadedBytes != null)
                          ? context.tr('kyc.doc.fileAttached')
                          : (current.fileName ??
                                context.tr('kyc.doc.fileAttached')),
                      key: const Key('kyc-doc-file-name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                context.tr('kyc.doc.fileHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              Wrap(
                spacing: FFTokens.spacingSm,
                runSpacing: FFTokens.spacingSm,
                children: [
                  FFButton(
                    key: const Key('kyc-doc-camera'),
                    label: context.tr('photo.camera'),
                    onPressed: _busy
                        ? null
                        : () => _upload(DocumentSource.camera),
                    variant: FFButtonVariant.secondary,
                    icon: Icons.photo_camera_outlined,
                  ),
                  FFButton(
                    key: const Key('kyc-doc-gallery'),
                    label: context.tr('photo.gallery'),
                    onPressed: _busy
                        ? null
                        : () => _upload(DocumentSource.gallery),
                    variant: FFButtonVariant.secondary,
                    icon: Icons.photo_library_outlined,
                  ),
                  FFButton(
                    key: const Key('kyc-doc-pdf'),
                    label: context.tr('kyc.doc.choosePdf'),
                    onPressed: _busy
                        ? null
                        : () => _upload(DocumentSource.file),
                    variant: FFButtonVariant.secondary,
                    icon: Icons.picture_as_pdf_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static bool _looksLikeImage(String name) =>
      RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(name);

  /// A 72 x 72 thumbnail of the file: the picture just uploaded, a preview
  /// fetched through the repository, or an icon for a PDF (or when the
  /// picture cannot be shown).
  Widget _filePreview(KycDocument doc) {
    const size = 72.0;
    final theme = Theme.of(context);
    Widget frame(Widget child) => Container(
      key: const Key('kyc-doc-preview'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: child,
    );
    Widget icon(IconData data) => frame(Center(child: Icon(data, size: 32)));
    Widget picture(Uint8List bytes) => frame(
      Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => icon(Icons.broken_image_outlined),
      ),
    );

    final fresh = _uploadedBytes;
    if (fresh != null) return picture(fresh);
    if (!doc.isImage) return icon(Icons.picture_as_pdf_outlined);
    final future = _previews.putIfAbsent(
      doc.id,
      () => widget.repository.documentFile(doc.id),
    );
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) return icon(Icons.image_outlined);
        if (!snap.hasData) {
          return frame(const Center(child: FFSpinner(size: 20)));
        }
        return picture(snap.data!);
      },
    );
  }

  static String _issuerLabel(String requirementKey) => switch (requirementKey) {
    'certification' => 'certificationBody',
    'liability_insurance' => 'insurer',
    _ => 'issuingAuthority',
  };

  static String _numberLabel(String requirementKey) => switch (requirementKey) {
    'owner_id' || 'trainer_id' || 'representative_id' => 'idNumber',
    'business_registration' => 'registrationNumber',
    'tin_certificate' => 'tin',
    'business_licence' => 'licenceNumber',
    'certification' => 'certificateNumber',
    'liability_insurance' => 'policyNumber',
    _ => 'documentNumber',
  };

  /// The checklist label that matches this document.
  static String _titleKey(String requirementKey) => switch (requirementKey) {
    'owner_id' || 'trainer_id' || 'representative_id' => 'id_document',
    'business_registration' => 'registration_certificate',
    'tin_certificate' => 'tin_certificate',
    'business_licence' => 'licence',
    'certification' => 'certification',
    'liability_insurance' => 'liability_cover',
    _ => requirementKey,
  };
}

// ── Payout accounts ─────────────────────────────────────────────────────────

class PayoutAccountsPage extends StatefulWidget {
  const PayoutAccountsPage({
    super.key,
    required this.repository,
    required this.overview,
  });
  final VerificationRepository repository;
  final KycOverview overview;

  @override
  State<PayoutAccountsPage> createState() => _PayoutAccountsPageState();
}

class _PayoutAccountsPageState extends State<PayoutAccountsPage> {
  late List<PayoutAccount> _accounts = widget.overview.accounts;
  bool _busy = false;

  Future<void> _reload() async {
    final data = await widget.repository.overview();
    if (mounted) setState(() => _accounts = data.accounts);
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AddAccountPage(repository: widget.repository),
      ),
    );
    if (added == true) await _reload();
  }

  Future<void> _remove(PayoutAccount a) async {
    setState(() => _busy = true);
    try {
      await widget.repository.removePayoutAccount(a.id);
      await _reload();
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('kyc.accounts.title'))),
    body: ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(context.tr('kyc.accounts.intro')),
        _gap(),
        if (_accounts.isEmpty)
          FFEmptyState(title: context.tr('kyc.accounts.empty'))
        else
          for (final a in _accounts)
            FFCard(
              key: Key('kyc-account-${a.id}'),
              margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Row(
                children: [
                  Icon(
                    a.method == 'bank'
                        ? Icons.account_balance_outlined
                        : Icons.phone_android_outlined,
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.method == 'bank' ? a.provider : context.tr('kyc.option.${a.provider}')} · ${a.accountNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(a.accountName),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            FFBadge(
                              label: context.tr('kyc.account.${a.status}'),
                              tone: switch (a.status) {
                                'verified' => FFBadgeTone.success,
                                'rejected' || 'disabled' => FFBadgeTone.danger,
                                _ => FFBadgeTone.warning,
                              },
                            ),
                            if (a.isPrimary)
                              FFBadge(
                                label: context.tr('kyc.account.primary'),
                                tone: FFBadgeTone.brand,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (a.status == 'pending_verification')
                    IconButton(
                      tooltip: context.tr('kyc.remove'),
                      onPressed: _busy ? null : () => _remove(a),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(FFTokens.spacingLg),
      child: FFButton(
        key: const Key('kyc-account-add'),
        label: context.tr('kyc.accounts.add'),
        onPressed: _busy ? null : _add,
        icon: Icons.add,
      ),
    ),
  );
}

/// The "my bank is not listed" choice in the bank list.
const _otherBank = '__other__';

class _AddAccountPage extends StatefulWidget {
  const _AddAccountPage({required this.repository});
  final VerificationRepository repository;

  @override
  State<_AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<_AddAccountPage> {
  final _form = GlobalKey<FormState>();
  String _method = 'mobile_money';
  String? _mobileProvider = 'mpesa';
  // A bank from the list, or [_otherBank] with its name typed in [_bank].
  String? _bankChoice;
  final _bank = TextEditingController();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _branch = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_bank, _name, _number, _branch]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.addPayoutAccount({
        'method': _method,
        'provider': _method != 'bank'
            ? _mobileProvider
            : _bankChoice == _otherBank
            ? _bank.text.trim()
            : _bankChoice,
        'accountName': _name.text.trim(),
        'accountNumber': _number.text.trim(),
        if (_method == 'bank' && _branch.text.trim().isNotEmpty)
          'branch': _branch.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: context.tr('kyc.accounts.add'),
    formKey: _form,
    busy: _busy,
    onSave: _save,
    children: [
      SegmentedButton<String>(
        key: const Key('kyc-account-method'),
        segments: [
          ButtonSegment(
            value: 'mobile_money',
            label: Text(context.tr('kyc.option.mobile_money')),
          ),
          ButtonSegment(
            value: 'bank',
            label: Text(context.tr('kyc.option.bank')),
          ),
        ],
        selected: {_method},
        onSelectionChanged: (s) => setState(() => _method = s.first),
      ),
      _gap(),
      if (_method == 'mobile_money')
        _choice(
          context,
          'provider',
          _mobileProvider,
          mobileMoneyProviders,
          (v) => setState(() => _mobileProvider = v),
          required: true,
        )
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: DropdownButtonFormField<String>(
            key: const Key('kyc-field-bank'),
            initialValue: _bankChoice,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '${context.tr('kyc.field.bank')} *',
              border: const OutlineInputBorder(),
            ),
            hint: Text(context.tr('kyc.field.bankChoose')),
            items: [
              for (final b in tanzaniaBanks)
                DropdownMenuItem(value: b, child: Text(b)),
              DropdownMenuItem(
                value: _otherBank,
                child: Text(context.tr('kyc.field.bankOther')),
              ),
            ],
            onChanged: (v) => setState(() => _bankChoice = v),
            validator: (v) => v == null ? context.tr('kyc.required') : null,
          ),
        ),
        // Only for a bank that is not in the list.
        if (_bankChoice == _otherBank)
          _text(context, 'bankName', _bank, required: true),
      ],
      _text(
        context,
        'accountName',
        _name,
        required: true,
        hintKey: 'kyc.hint.accountName',
      ),
      _text(
        context,
        _method == 'bank' ? 'accountNumber' : 'mobileNumber',
        _number,
        required: true,
        keyboard: _method == 'bank'
            ? TextInputType.number
            : TextInputType.phone,
      ),
      if (_method == 'bank') _text(context, 'branch', _branch),
      Text(
        context.tr('kyc.accounts.verifyNote'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

/// One agreement (partner terms or verification consent) to read and accept.
/// Returns the refreshed overview once accepted.
class AgreementPage extends StatefulWidget {
  const AgreementPage({
    super.key,
    required this.repository,
    required this.agreementType,
  });

  final VerificationRepository repository;
  final String agreementType;

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  KycAgreement? _agreement;
  Object? _loadError;
  bool _agreed = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_agreement == null && _loadError == null) _load();
  }

  Future<void> _load() async {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    try {
      final list = await widget.repository.agreements(lang);
      final match = list.where((a) => a.agreementType == widget.agreementType);
      if (!mounted) return;
      setState(() {
        _agreement = match.isEmpty ? null : match.first;
        _loadError = match.isEmpty ? StateError('not_found') : null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.acceptAgreement(_agreement!);
      if (!mounted) return;
      _snack(context, context.tr('kyc.agreement.done'));
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _agreement;
    return Scaffold(
      appBar: AppBar(
        title: Text(a?.title ?? context.tr('kyc.agreement.title')),
      ),
      body: a == null
          ? Center(
              child: _loadError == null
                  ? FFSpinner(size: 32)
                  : Padding(
                      padding: const EdgeInsets.all(FFTokens.spacingLg),
                      child: Text(context.tr('kyc.agreement.loadFailed')),
                    ),
            )
          : ListView(
              key: const Key('kyc-agreement-text'),
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  [
                    ?a.reference,
                    context
                        .tr('kyc.agreement.version')
                        .replaceFirst('{v}', a.version),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final s in a.sections) ...[
                  _gap(),
                  Text(
                    s.heading,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(s.text),
                ],
                _gap(),
                if (a.accepted)
                  FFAlert(
                    key: const Key('kyc-agreement-accepted'),
                    tone: FFAlertTone.success,
                    message: context
                        .tr('kyc.agreement.accepted')
                        .replaceFirst(
                          '{date}',
                          a.acceptedAt!.toLocal().toIso8601String().substring(
                            0,
                            10,
                          ),
                        ),
                  )
                else
                  CheckboxListTile(
                    key: const Key('kyc-agreement-check'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agreed,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _agreed = v ?? false),
                    title: Text(context.tr('kyc.agreement.confirm')),
                  ),
              ],
            ),
      bottomNavigationBar: a == null || a.accepted
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(FFTokens.spacingLg),
              child: FFButton(
                key: const Key('kyc-agreement-accept'),
                label: context.tr('kyc.agreement.accept'),
                onPressed: _busy || !_agreed ? null : _accept,
                loading: _busy,
              ),
            ),
    );
  }
}
