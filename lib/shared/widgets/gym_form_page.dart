import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../media/media_src.dart';
import 'location_picker.dart';
import '../api_error_message.dart';

/// Fullscreen form for creating/editing a gym. Mirrors the fields used during
/// gym-owner onboarding (registration page) so all gym-creation paths produce
/// the same data shape. Returns the full payload `Map<String, dynamic>` on
/// save, or `null` if cancelled.
class GymFormPage extends StatefulWidget {
  /// Existing gym data when editing; `null` for create.
  final Map<String, dynamic>? initial;

  /// Optional title override.
  final String? title;

  const GymFormPage({super.key, this.initial, this.title});

  @override
  State<GymFormPage> createState() => _GymFormPageState();
}

class _GymFormPageState extends State<GymFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _rateDayCtrl;
  late final TextEditingController _rateWeekCtrl;
  late final TextEditingController _rateMonthCtrl;

  /// Owner-set trainer-pass fee per period (empty = not sold).
  final Map<String, TextEditingController> _trainerPassFees = {
    for (final p in _passPeriods) p: TextEditingController(),
  };
  String _tier = 'standard';
  bool _trainerPassEnabled = false;

  static const _passPeriods = ['daily', 'weekly', 'monthly'];
  final List<Map<String, dynamic>> _classes = [];
  double? _lat;
  double? _lng;

  /// Mix of existing remote URLs/data-URIs (kept as-is) and new local file
  /// paths (converted to WebP + encoded to base64 on save).
  final List<String> _images = [];

  /// Paths in [_images] picked on this device in this form. Only these are
  /// read from local files; everything else came from the server and is
  /// drawn (and sent back) as stored, through the image source check.
  final Set<String> _localPicks = {};

  /// Small WebP thumbnail counterpart for each entry in [_images] (same
  /// index = same photo). `null` means "not generated yet" — filled in on
  /// save, either by compressing a new local file or reusing an existing
  /// pre-thumbnail image as its own thumbnail.
  final List<String?> _thumbnails = [];

  static const int _fullMaxDimension = 1280;
  static const int _fullWebpQuality = 80;
  static const int _thumbMaxDimension = 320;
  static const int _thumbWebpQuality = 70;

  /// Selected trainer ids
  final List<String> _trainerIds = [];

  /// Trainers linked to this gym when the form opened; null until loaded (or
  /// when loading failed). The PUT body sends `trainerIds` only when the owner
  /// changed this set: the server treats the list as the gym's full set and
  /// unlinks anyone missing from it.
  Set<String>? _linkedTrainerIds;

  /// Only trainers already linked to this gym. New trainers join through
  /// their own join request, which the owner approves on the Trainers page.
  List<Map<String, dynamic>> _trainers = [];
  bool _loadingTrainers = false;
  bool _trainersFailed = false;

  String? get _gymId {
    final id = widget.initial?['id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final g = widget.initial ?? const {};
    _nameCtrl = TextEditingController(text: g['name']?.toString() ?? '');
    _locationCtrl = TextEditingController(
      text: g['location']?.toString() ?? '',
    );
    _rateDayCtrl = TextEditingController(
      text: _numText(g['ratePerDay'] ?? g['perVisitRate']),
    );
    _rateWeekCtrl = TextEditingController(text: _numText(g['ratePerWeek']));
    _rateMonthCtrl = TextEditingController(text: _numText(g['ratePerMonth']));
    final trainerPass = g['trainerPass'];
    if (trainerPass is Map) {
      _trainerPassEnabled = trainerPass['enabled'] == true;
      final options = trainerPass['options'];
      if (options is Map) {
        for (final p in _passPeriods) {
          final fee = options[p];
          if (fee is num && fee > 0) _trainerPassFees[p]!.text = _numText(fee);
        }
      } else {
        // Older single-fee shape: { feeTzs, period }.
        final period = trainerPass['period']?.toString();
        final fee = trainerPass['feeTzs'];
        if (_passPeriods.contains(period) && fee is num && fee > 0) {
          _trainerPassFees[period]!.text = _numText(fee);
        }
      }
    }
    final classes = g['classes'];
    if (classes is List) {
      _classes.addAll(
        classes.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
      );
    }
    _tier = (g['tier']?.toString().isNotEmpty ?? false)
        ? g['tier'].toString()
        : 'standard';
    final coords = g['coordinates'];
    if (coords is Map) {
      _lat = (coords['lat'] as num?)?.toDouble();
      _lng = (coords['lng'] as num?)?.toDouble();
    }
    final imgs = g['images'];
    if (imgs is List) {
      _images.addAll(imgs.whereType<String>());
    }
    final thumbs = g['thumbnails'];
    final existingThumbs = thumbs is List
        ? thumbs.whereType<String>().toList()
        : <String>[];
    for (var i = 0; i < _images.length; i++) {
      _thumbnails.add(i < existingThumbs.length ? existingThumbs[i] : null);
    }
    if (_gymId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTrainers());
    }
  }

  String _numText(dynamic v) {
    if (v == null) return '';
    final n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return n == 0 ? '' : n.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _rateDayCtrl.dispose();
    _rateWeekCtrl.dispose();
    _rateMonthCtrl.dispose();
    for (final c in _trainerPassFees.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Loads the trainers linked to this gym (gym rows carry no trainer list;
  /// the link lives on the trainer) and selects them all.
  Future<void> _loadTrainers() async {
    final gymId = _gymId!;
    setState(() => _loadingTrainers = true);
    final api = AppScope.of(context).api;
    try {
      final result = await api.ownerTrainers(gymId: gymId);
      final linked = result
          .whereType<Map>()
          .map((t) => Map<String, dynamic>.from(t))
          .where((t) {
            // The server falls back to all the owner's gyms for an unknown id.
            final ids = t['gymIds'];
            return ids is! List || ids.contains(gymId);
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _trainers = linked;
        _linkedTrainerIds = {
          for (final t in linked)
            if ((t['id']?.toString() ?? '').isNotEmpty) t['id'].toString(),
        };
        _trainerIds
          ..clear()
          ..addAll(_linkedTrainerIds!);
        _loadingTrainers = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingTrainers = false;
          _trainersFailed = true;
        });
      }
    }
  }

  /// True when the owner unticked (or re-ticked) a linked trainer.
  bool get _trainersChanged {
    final linked = _linkedTrainerIds;
    if (linked == null) return false;
    final selected = _trainerIds.toSet();
    return selected.length != linked.length || !selected.containsAll(linked);
  }

  /// Room left under the server's cap (kGymMaxPhotos, too_many_images).
  int get _photoRoom => kGymMaxPhotos - _images.length;

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
      _images.addAll(files.map((file) => file.path));
      _localPicks.addAll(files.map((file) => file.path));
      _thumbnails.addAll(List<String?>.filled(files.length, null));
    });
    if (picked.length > files.length) _sayPhotoMax();
  }

  void _sayPhotoMax() => FFSnack.info(
    context,
    context.tr('photos.max').replaceAll('{n}', '$kGymMaxPhotos'),
  );

  /// Downscales+re-encodes a local image file as WebP. Returns `null` if the
  /// file can't be read or compressed (e.g. unsupported platform/format).
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

  /// Builds the final `images`/`thumbnails` payload arrays. New local files
  /// are converted to WebP (full + thumbnail); pre-existing remote
  /// URLs/data-URIs are kept as-is, reusing the full image as its own
  /// thumbnail when no dedicated thumbnail was recorded.
  Future<(List<String>, List<String>)> _encodeImages() async {
    final outImages = <String>[];
    final outThumbnails = <String>[];
    for (var i = 0; i < _images.length; i++) {
      final p = _images[i];
      final existingThumb = i < _thumbnails.length ? _thumbnails[i] : null;

      // A stored photo (data URI, /storage path or URL): keep as-is. The
      // server accepts stored values unchanged (fitflex-functions#273).
      if (!_localPicks.contains(p)) {
        outImages.add(p);
        outThumbnails.add(existingThumb ?? p);
        continue;
      }

      try {
        final f = File(p);
        if (!await f.exists()) continue;
        final fullWebp = await _compressToWebpDataUrl(
          p,
          maxDimension: _fullMaxDimension,
          quality: _fullWebpQuality,
        );
        final thumbWebp = await _compressToWebpDataUrl(
          p,
          maxDimension: _thumbMaxDimension,
          quality: _thumbWebpQuality,
        );
        if (fullWebp != null) {
          outImages.add(fullWebp);
          outThumbnails.add(thumbWebp ?? fullWebp);
        } else {
          // Compression unavailable (e.g. web) — fall back to the raw bytes.
          final bytes = await f.readAsBytes();
          final ext = p.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
          outImages.add(dataUrl);
          outThumbnails.add(dataUrl);
        }
      } catch (_) {
        // Skip unreadable file
      }
    }
    return (outImages, outThumbnails);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final (images, thumbnails) = await _encodeImages();
      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'tier': _tier,
        'ratePerDay': num.tryParse(_rateDayCtrl.text) ?? 0,
        'ratePerWeek': num.tryParse(_rateWeekCtrl.text) ?? 0,
        'ratePerMonth': num.tryParse(_rateMonthCtrl.text) ?? 0,
        'perVisitRate': num.tryParse(_rateDayCtrl.text) ?? 0,
        'venueType': 'physical',
        'accessMode': 'paid_visit',
        if (_lat != null && _lng != null)
          'coordinates': {'lat': _lat, 'lng': _lng},
        'images': images,
        'thumbnails': thumbnails,
        // Omitted unless changed, so an edit of hours or photos never
        // unlinks the gym's trainers.
        if (_trainersChanged) 'trainerIds': List<String>.from(_trainerIds),
        'classes': _classes,
        'trainerPass': {
          'enabled': _trainerPassEnabled,
          'options': {
            for (final p in _passPeriods)
              p: num.tryParse(_trainerPassFees[p]!.text.trim()) ?? 0,
          },
        },
      };
      if (!mounted) return;
      Navigator.of(context).pop(payload);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(FFLocaleScope.of(context), e))),
        );
      }
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  String? _optionalFee(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    return n == null || n < 0 ? context.tr('onboarding.required') : null;
  }

  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) {
      return context.tr('onboarding.required');
    }
    final n = num.tryParse(v.trim());
    if (n == null || n < 0) return context.tr('onboarding.required');
    return null;
  }

  String? _optionalNonNegativeNumber(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = num.tryParse(v.trim());
    return n == null || n < 0 ? context.tr('onboarding.required') : null;
  }

  Future<void> _showClassEditor({int? index}) async {
    final existing = index == null
        ? const <String, dynamic>{}
        : _classes[index];
    final name = TextEditingController(
      text: existing['name']?.toString() ?? '',
    );
    final schedule = TextEditingController(
      text: existing['schedule']?.toString() ?? '',
    );
    final price = TextEditingController(text: _numText(existing['price']));
    final location = TextEditingController(
      text: existing['location']?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('ownerReg.classEditorTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FFTextField(
                key: const Key('gym-class-name'),
                controller: name,
                label: context.tr('ownerReg.className'),
              ),
              FFTextField(
                key: const Key('gym-class-schedule'),
                controller: schedule,
                label: context.tr('ownerReg.classSchedule'),
              ),
              FFTextField(
                key: const Key('gym-class-price'),
                controller: price,
                label: context.tr('ownerReg.classPrice'),
                keyboardType: TextInputType.number,
              ),
              FFTextField(
                key: const Key('gym-class-location'),
                controller: location,
                label: context.tr('ownerReg.classLocation'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            key: const Key('gym-class-save'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('member.save')),
          ),
        ],
      ),
    );
    if (saved == true && name.text.trim().isNotEmpty && mounted) {
      setState(() {
        final item = <String, dynamic>{
          if (existing['id'] != null) 'id': existing['id'],
          'name': name.text.trim(),
          'schedule': schedule.text.trim(),
          'price': num.tryParse(price.text.trim()) ?? 0,
          'location': location.text.trim(),
        };
        if (index == null) {
          _classes.add(item);
        } else {
          _classes[index] = item;
        }
      });
    }
    // The dialog route is still animating out immediately after `await
    // showDialog`; disposing now can leave its TextFields rebuilding against
    // disposed controllers. Release them after that transition settles.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      name.dispose();
      schedule.dispose();
      price.dispose();
      location.dispose();
    });
  }

  List<Widget> _trainerSection(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    if (_gymId == null) {
      return [
        Text(
          context.tr('ownerReg.trainersJoinHint'),
          key: const Key('gym-trainers-join-hint'),
          style: small,
        ),
      ];
    }
    if (_loadingTrainers) {
      return const [
        Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
      ];
    }
    if (_trainersFailed) {
      return [
        Text(
          context.tr('ownerReg.trainersLoadFailed'),
          key: const Key('gym-trainers-load-failed'),
          style: small,
        ),
      ];
    }
    if (_trainers.isEmpty) {
      return [
        Text(
          context.tr('ownerReg.noLinkedTrainers'),
          key: const Key('gym-trainers-none'),
          style: small,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(context.tr('ownerReg.trainersJoinHint'), style: small),
      ];
    }
    return [
      Text(context.tr('ownerReg.trainersLinkedHint'), style: small),
      const SizedBox(height: FFTokens.spacingXs),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _trainers.map((t) {
          final id = t['id']?.toString() ?? '';
          final name =
              (t['displayName'] as String?) ?? (t['email'] as String?) ?? id;
          return FilterChip(
            key: Key('gym-trainer-chip-$id'),
            label: Text(name),
            selected: _trainerIds.contains(id),
            onSelected: (v) => setState(() {
              if (v) {
                if (!_trainerIds.contains(id)) _trainerIds.add(id);
              } else {
                _trainerIds.remove(id);
              }
            }),
          );
        }).toList(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (isEdit
                  ? context.tr('owner.editGym')
                  : context.tr('owner.addGym')),
        ),
        leading: IconButton(
          tooltip: context.tr('common.close'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const Key('gym-form-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? FFSpinner(size: 18)
                : Text(context.tr('member.save')),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            key: const Key('gym-form-scroll'),
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              FFTextField(
                controller: _nameCtrl,
                label: context.tr('ownerReg.gymName'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _locationCtrl,
                label: context.tr('ownerReg.gymLocation'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _rateDayCtrl,
                keyboardType: TextInputType.number,
                label: context.tr('ownerReg.ratePerDay'),
                validator: _requiredNumber,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _rateWeekCtrl,
                keyboardType: TextInputType.number,
                label: context.tr('ownerReg.ratePerWeek'),
                validator: _optionalNonNegativeNumber,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                controller: _rateMonthCtrl,
                keyboardType: TextInputType.number,
                label: context.tr('ownerReg.ratePerMonth'),
                validator: _optionalNonNegativeNumber,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.trainersLabel')),
              ..._trainerSection(context),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.classesLabel')),
              if (_classes.isEmpty)
                Text(
                  context.tr('ownerReg.noClasses'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ..._classes.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value['name']?.toString() ?? ''),
                    subtitle: Text(
                      [entry.value['schedule'], entry.value['location']]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: context.tr('ownerReg.editClass'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showClassEditor(index: entry.key),
                    ),
                  ),
                ),
              FFButton(
                key: const Key('gym-add-class'),
                label: context.tr('ownerReg.addClass'),
                onPressed: _showClassEditor,
                variant: FFButtonVariant.secondary,
                icon: Icons.add,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.trainerPassLabel')),
              SwitchListTile(
                key: const Key('gym-trainer-pass-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('ownerReg.trainerPassEnabled')),
                value: _trainerPassEnabled,
                onChanged: (value) =>
                    setState(() => _trainerPassEnabled = value),
              ),
              Text(
                context.tr('ownerReg.trainerPassHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_trainerPassEnabled) ...[
                const SizedBox(height: FFTokens.spacingSm),
                for (final p in _passPeriods) ...[
                  FFTextField(
                    key: Key('gym-trainer-pass-fee-$p'),
                    controller: _trainerPassFees[p],
                    keyboardType: TextInputType.number,
                    label: context.tr('ownerReg.trainerPassFee_$p'),
                    hint: context.tr('ownerReg.trainerPassFeeOptional'),
                    validator: _optionalFee,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                ],
                FormField<void>(
                  validator: (_) =>
                      _passPeriods.any(
                        (p) =>
                            (num.tryParse(_trainerPassFees[p]!.text.trim()) ??
                                0) >
                            0,
                      )
                      ? null
                      : context.tr('ownerReg.trainerPassNeedsFee'),
                  builder: (field) => field.hasError
                      ? Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.mapLabel')),
              LocationPicker(
                initialLat: _lat,
                initialLng: _lng,
                height: 200,
                onChanged: (latlng) {
                  _lat = latlng.latitude;
                  _lng = latlng.longitude;
                },
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('ownerReg.imagesLabel')),
              if (_images.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, separatorIndex) =>
                        const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final src = _images[i];
                      // Only this form's own picks are read from files; a
                      // stored photo goes through the source check.
                      final widgetImg = _localPicks.contains(src)
                          ? Image.file(
                              File(src),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stackTrace) =>
                                  const Icon(Icons.broken_image),
                            )
                          : FFRemoteImage(
                              src: src,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              fallback: const Icon(Icons.broken_image),
                            );
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              FFTokens.radiusMd,
                            ),
                            child: widgetImg,
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                final removed = _images.removeAt(i);
                                if (!_images.contains(removed)) {
                                  _localPicks.remove(removed);
                                }
                                if (i < _thumbnails.length) {
                                  _thumbnails.removeAt(i);
                                }
                              }),
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper to push the form as a fullscreen dialog.
Future<Map<String, dynamic>?> openGymForm(
  BuildContext context, {
  Map<String, dynamic>? initial,
  String? title,
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GymFormPage(initial: initial, title: title),
    ),
  );
}
