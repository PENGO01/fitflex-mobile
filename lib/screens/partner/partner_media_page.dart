import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/partner_media/partner_hero_builder.dart';
import '../../shared/partner_media/partner_media_image_check.dart';
import '../../shared/partner_media/partner_media_models.dart';
import '../../shared/partner_media/partner_media_store.dart';
import 'partner_media_band.dart';
import 'partner_media_sheet.dart';

/// Picks a photo from [source] for tests; null: the real picker.
@visibleForTesting
Future<PickedPartnerImage?> Function(ImageSource source)?
debugPartnerMediaPicker;

/// Reads a picked file: its bytes as they are (never downscaled), its type
/// from its first bytes, and its size from its header.
Future<PickedPartnerImage?> pickPartnerImage(ImageSource source) async {
  final picker = debugPartnerMediaPicker;
  if (picker != null) return picker(source);
  final file = await ImagePicker().pickImage(source: source);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final size = await readImageSize(bytes);
  return PickedPartnerImage(
    bytes: bytes,
    filename: file.name.isEmpty ? 'upload' : file.name,
    type: sniffImageType(bytes),
    width: size?.width,
    height: size?.height,
  );
}

enum _Phase { loading, ready, error, offline, noAccess, noGym, off }

/// Settings → "Home photo and logo" (spec §41), one page for all three
/// roles: `/owner/brand-media?gymId=`, `/trainer/brand-media`,
/// `/vendor/brand-media`. Shows the live photo and logo (or the last FitFlex
/// takedown, with its reason and note), uploads, replaces and removes them.
/// Whoever may not change them (`canEdit: false`, another gym) sees a "no
/// access" page.
class PartnerMediaPage extends StatefulWidget {
  const PartnerMediaPage({super.key, required this.side, this.gymId});

  /// `gym`, `trainer` or `vendor`.
  final String side;

  /// Owners: the gym, from the link or the app bar's pick.
  final String? gymId;

  @override
  State<PartnerMediaPage> createState() => _PartnerMediaPageState();
}

class _PartnerMediaPageState extends State<PartnerMediaPage> {
  _Phase _phase = _Phase.loading;
  PartnerMediaOverview? _o;
  PartnerHeroMedia? _saved;
  List<Map<String, dynamic>> _gyms = const [];
  String? _gymId;
  bool _started = false;

  /// The signed-in role is not this page's (generic "no access" text).
  bool _wrongRole = false;

  /// The gym from the link, kept for Back from a cold start (§41.1), so a
  /// gym picked on this page never changes the app bar's gym.
  String? _linkedGymId;

  /// The kind being uploaded, and its progress (the card shows it too).
  String? _uploadKind;
  PartnerUploadProgress? _progress;
  Uint8List? _uploadThumb;
  final Map<String, String> _cardError = {};
  String? _removing;

  bool get _gym => widget.side == 'gym';
  String get _lang => FFLocaleScope.of(context).locale.languageCode;
  ApiClient get _api => AppScope.of(context).api;

  String? get _accountId => AppScope.of(context).auth.user?['id']?.toString();

  PartnerMediaSubject? get _subject {
    final id = _accountId;
    if (id == null) return null;
    return switch (widget.side) {
      'gym' => _gymId == null ? null : PartnerMediaSubject.gym(id, _gymId!),
      'trainer' => PartnerMediaSubject.trainer(id),
      _ => PartnerMediaSubject.vendor(id),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _gymId = widget.gymId;
    _linkedGymId = widget.gymId;
    unawaited(_load());
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _phase = _Phase.loading);
    final auth = AppScope.of(context).auth;
    final role = auth.user?['userType']?.toString() ?? auth.role;
    if (partnerMediaSideOf(role) != widget.side) {
      // Another role's page (a member opening /trainer/brand-media): the
      // generic wording, not the gym or business owner's.
      setState(() {
        _wrongRole = true;
        _phase = _Phase.noAccess;
      });
      return;
    }
    try {
      if (_gym) {
        final gyms = (await _api.ownerGyms()).whereType<Map>().map(
          (g) => Map<String, dynamic>.from(g),
        );
        _gyms = gyms.toList();
        if (_gyms.isEmpty) {
          if (mounted) setState(() => _phase = _Phase.noGym);
          return;
        }
        _gymId ??= _gyms.first['id']?.toString();
      }
      final raw = await _api.partnerMedia(gymId: _gym ? _gymId : null);
      final o = PartnerMediaOverview.tryParse(raw);
      if (!mounted) return;
      if (o == null) {
        setState(() => _phase = _Phase.error);
        return;
      }
      if (!o.canEdit) {
        setState(() => _phase = _Phase.noAccess);
        return;
      }
      _o = o;
      final store = PartnerMediaStore.instance;
      final subject = _subject;
      if (store != null && subject != null) {
        await store.apply(subject, o);
      }
      if (!mounted) return;
      setState(() {
        _saved = store?.readyFor(subject);
        _phase = _Phase.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = switch ((e.status, e.code)) {
          (404, 'feature_disabled') => _Phase.off,
          (403, _) => _Phase.noAccess,
          (400, 'gym_id_required') => _Phase.noGym,
          _ => _Phase.error,
        };
      });
    } catch (_) {
      // No answer: the last saved copy, with uploads switched off.
      if (!mounted) return;
      setState(() {
        _saved = PartnerMediaStore.instance?.readyFor(_subject);
        _phase = _Phase.offline;
      });
    }
  }

  // ── choosing and uploading ──────────────────────────────────────────────

  Future<PickedPartnerImage?> _choose() async {
    ImageSource? source = ImageSource.gallery;
    if (!kIsWeb) {
      source = await showFFSheet<ImageSource>(
        context,
        title: context.tr('partnerMedia.title'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FFActionTile(
              key: const Key('partner-media-source-gallery'),
              icon: Icons.photo_library_outlined,
              title: context.tr('partnerMedia.sheet.gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            FFActionTile(
              key: const Key('partner-media-source-camera'),
              icon: Icons.photo_camera_outlined,
              title: context.tr('partnerMedia.sheet.camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      );
    }
    if (source == null) return null;
    try {
      return await pickPartnerImage(source);
    } catch (_) {
      return null;
    }
  }

  Future<void> _start(String kind) async {
    final o = _o;
    final confirmation = o?.confirmation;
    if (o == null || confirmation == null || _phase != _Phase.ready) return;
    final picked = await _choose();
    if (picked == null || !mounted) return;
    setState(() => _cardError.remove(kind));
    final status = await showPartnerMediaUploadSheet(
      context,
      kind: kind,
      side: widget.side,
      picked: picked,
      confirmation: confirmation,
      limits: o.limits,
      name: _bandName,
      replacing: o.live(kind) != null,
      livePhoto: _saved?.photo,
      liveLogo: _saved?.logo,
      upload: _upload,
      pickAnother: _choose,
      reloadConfirmation: () async {
        await _load(quiet: true);
        return _o?.confirmation;
      },
    );
    if (!mounted) return;
    setState(() {
      _uploadKind = null;
      _progress = null;
      _uploadThumb = null;
    });
    if (status == PartnerUploadStatus.ok) {
      FFSnack.success(
        context,
        context.tr(
          kind == 'logo'
              ? 'partnerMedia.liveNowLogo'
              : 'partnerMedia.liveNowHero',
        ),
      );
    } else if (status == PartnerUploadStatus.noAccess) {
      setState(() => _phase = _Phase.noAccess);
    }
  }

  Future<PartnerUploadResult> _upload(
    PartnerUploadRequest r,
    PartnerUploadProgress progress,
    Future<void> abort,
  ) async {
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    setState(() {
      _uploadKind = r.kind;
      _progress = progress;
      _uploadThumb = r.picked.bytes;
    });
    String f(double v) => v.toStringAsFixed(3);
    final fields = <String, String>{
      'rightsConfirmed': 'true',
      'confirmationVersion': r.confirmationVersion,
      if (_gym && _gymId != null) 'gymId': _gymId!,
      if (r.kind == 'logo') ...{
        'ownLogoConfirmed': 'true',
        'plate': r.plate,
      } else ...{
        'focalX': f(r.focal.x),
        'focalY': f(r.focal.y),
      },
    };
    PartnerUploadResult done(PartnerUploadResult res) {
      if (mounted) {
        setState(() {
          _uploadKind = null;
          _progress = null;
          _uploadThumb = null;
        });
      }
      return res;
    }

    try {
      await _api.partnerMediaUpload(
        r.kind,
        bytes: r.picked.bytes,
        filename: r.picked.filename,
        fields: fields,
        abortTrigger: abort,
        onProgress: (sent, total) {
          if (total <= 0) return;
          progress.update(sent / total);
          if (sent >= total && !progress.preparing) progress.setPreparing();
        },
      );
      // Live on the server even if Cancel came too late: show what is true.
      if (mounted) await _load(quiet: true);
      if (cancelled) {
        return done(const PartnerUploadResult(PartnerUploadStatus.cancelled));
      }
      return done(const PartnerUploadResult(PartnerUploadStatus.ok));
    } on ApiException catch (e) {
      if (cancelled) {
        return done(const PartnerUploadResult(PartnerUploadStatus.cancelled));
      }
      final code = e.code ?? 'unknown';
      final body = e.body is Map
          ? Map<String, Object?>.from(e.body as Map)
          : const <String, Object?>{};
      if (code == 'confirmation_version_mismatch') {
        return done(
          const PartnerUploadResult(PartnerUploadStatus.versionMismatch),
        );
      }
      if (code == 'not_your_gym' || code == 'acl_forbidden') {
        return done(const PartnerUploadResult(PartnerUploadStatus.noAccess));
      }
      if (code == 'not_editable') unawaited(_load(quiet: true));
      return done(
        PartnerUploadResult(
          PartnerUploadStatus.failed,
          code: code,
          values: body,
        ),
      );
    } on http.RequestAbortedException {
      return done(const PartnerUploadResult(PartnerUploadStatus.cancelled));
    } catch (_) {
      if (cancelled) {
        return done(const PartnerUploadResult(PartnerUploadStatus.cancelled));
      }
      return done(const PartnerUploadResult(PartnerUploadStatus.offline));
    }
  }

  Future<void> _remove(PartnerMediaItem item) async {
    final logo = item.isLogo;
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr(
        logo ? 'partnerMedia.removeLogoTitle' : 'partnerMedia.removeHeroTitle',
      ),
      message: context.tr(
        logo ? 'partnerMedia.removeLogoBody' : 'partnerMedia.removeHeroBody',
      ),
      confirmLabel: context.tr('partnerMedia.remove'),
      destructive: true,
      confirmKey: const Key('partner-media-remove-confirm'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _removing = item.kind;
      _cardError.remove(item.kind);
    });
    try {
      await _api.partnerMediaRemove(item.id);
      if (!mounted) return;
      await _load(quiet: true);
      if (mounted) FFSnack.success(context, context.tr('partnerMedia.removed'));
    } on ApiException catch (e) {
      if (!mounted) return;
      final code = e.code ?? 'unknown';
      if (code == 'not_your_gym' || code == 'acl_forbidden') {
        setState(() => _phase = _Phase.noAccess);
      } else if (code == 'media_not_found') {
        // Already gone (removed by a teammate, replaced, taken down): the
        // outcome the person asked for, so no error; show what is true now.
        await _load(quiet: true);
        if (mounted) {
          FFSnack.success(context, context.tr('partnerMedia.removed'));
        }
      } else if (e.status == 404 && code == 'feature_disabled') {
        setState(() => _phase = _Phase.off);
      } else {
        if (code == 'not_editable') {
          await _load(quiet: true);
        }
        if (mounted) {
          setState(
            () => _cardError[item.kind] = partnerMediaErrorText(
              context,
              item.kind,
              code,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _cardError[item.kind] = context.tr('partnerMedia.offline'),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = null);
    }
  }

  Future<void> _pickGym() async {
    final picked = await showFFSheet<String>(
      context,
      title: context.tr('partnerMedia.chooseGym'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in _gyms)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: FFChoiceTile(
                title: g['name']?.toString() ?? '',
                selected: g['id']?.toString() == _gymId,
                onSelected: () =>
                    Navigator.of(context).pop(g['id']?.toString()),
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == _gymId || !mounted) return;
    // The address follows the gym shown (a reload or a shared link opens
    // the same gym), without a new history entry or a page rebuild.
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(partnerMediaRoute('gym', gymId: picked)),
      replace: true,
    );
    setState(() {
      _gymId = picked;
      _o = null;
      _saved = null;
    });
    unawaited(_load());
  }

  // ── building ────────────────────────────────────────────────────────────

  bool get _wide => MediaQuery.sizeOf(context).width >= 840;

  String? get _gymName => _gyms
      .where((g) => g['id']?.toString() == _gymId)
      .map((g) => g['name']?.toString())
      .firstOrNull;

  /// The band's name: the person (greeting) or the business.
  String? get _bandName {
    if (widget.side == 'vendor') return _o?.subjectName;
    final u = AppScope.of(context).auth.user;
    return u?['displayName']?.toString();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(switch (widget.side) {
      'gym' =>
        _linkedGymId == null
            ? '/owner/home'
            : Uri(
                path: '/owner/home',
                queryParameters: {'gymId': _linkedGymId!},
              ).toString(),
      'trainer' => '/trainer/home',
      _ => '/vendor/home',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('partner-media-back'),
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        // Long in Swahili at 1.3x ("Picha ya mwanzo na nembo"): up to two
        // lines, shrunk to fit the bar rather than cut.
        centerTitle: false,
        titleSpacing: 0,
        // Long in Swahili ("Picha ya mwanzo na nembo"): up to two lines,
        // shrunk to fit, and kept 16px off the bar's far edge.
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: FFTokens.spacingMd),
          child: Semantics(
            header: true,
            child: LayoutBuilder(
              // Never taller than the bar: at 1.3x two lines are shrunk.
              builder: (context, c) => ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: kToolbarHeight - 4,
                ),
                child: FittedBox(
                key: const Key('partner-media-title'),
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth),
                  child: Text(
                    context.tr('partnerMedia.title'),
                    maxLines: 2,
                    softWrap: true,
                  ),
                ),
              ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _blocked(String key, {IconData icon = Icons.lock_outline}) => ListView(
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    children: [
      FFEmptyState(
        key: Key('partner-media-$key'),
        icon: icon,
        title: context.tr(key),
        action: FFButton(
          label: context.tr('a11y.back'),
          variant: FFButtonVariant.secondary,
          onPressed: _back,
        ),
      ),
    ],
  );

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.noAccess:
        return _blocked(switch (widget.side) {
          _ when _wrongRole => 'partnerMedia.restricted',
          'vendor' => 'partnerMedia.restrictedVendor',
          'gym' => 'partnerMedia.restrictedGym',
          _ => 'partnerMedia.restricted',
        });
      case _Phase.noGym:
        return _blocked('partnerMedia.noGym', icon: Icons.fitness_center);
      case _Phase.off:
        return _blocked('partnerMedia.off', icon: Icons.hourglass_empty);
      case _Phase.error:
        return ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            _previewCard(context),
            const SizedBox(height: FFTokens.spacingLg),
            FFErrorState(
              key: const Key('partner-media-load-error'),
              message: context.tr('partnerMedia.loadError'),
              retryLabel: context.tr('common.retry'),
              onRetry: () => _load(),
            ),
          ],
        );
      case _Phase.loading:
      case _Phase.ready:
      case _Phase.offline:
        break;
    }
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final hero = _card(context, 'hero');
    final logo = _card(context, 'logo');
    return ListView(
      key: const Key('partner-media-list'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        if (_phase == _Phase.offline) ...[
          Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('partner-media-offline'),
              tone: FFAlertTone.warning,
              message: context.tr('partnerMedia.offline'),
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        if (_gym && _gyms.length > 1) ...[
          FFActionTile(
            key: const Key('partner-media-gym'),
            icon: Icons.fitness_center,
            title: context
                .tr('partnerMedia.gym')
                .replaceAll('{gym}', _gymName ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: _phase == _Phase.loading ? null : _pickGym,
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        _previewCard(context),
        const SizedBox(height: FFTokens.spacingLg),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: hero),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(child: logo),
            ],
          )
        else ...[
          hero,
          const SizedBox(height: FFTokens.spacingMd),
          logo,
        ],
        const SizedBox(height: FFTokens.spacingLg),
        FFAlert(message: context.tr('partnerMedia.reviewNote')),
        const SizedBox(height: FFTokens.spacingMd),
        _rulesCard(context),
        if (widget.side == 'vendor') ...[
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            key: const Key('partner-media-vendor-note'),
            context
                .tr('partnerMedia.vendorNote')
                .replaceAll('{editProfile}', context.tr('vendor.editProfile')),
          ),
        ],
      ],
    );
  }

  Widget _previewCard(BuildContext context) {
    // Loading: the bundled photo or the saved copy, and no plate yet (§41.3).
    final loading = _phase == _Phase.loading;
    final saved =
        _saved ??
        (loading ? PartnerMediaStore.instance?.readyFor(_subject) : null);
    final photo = saved?.photo;
    final logo = loading ? null : saved?.logo;
    final label = context
        .tr('partnerMedia.a11y.preview')
        .replaceAll(
          '{photo}',
          context.tr(
            photo == null
                ? 'partnerMedia.a11y.fitflexPhoto'
                : 'partnerMedia.a11y.yourPhoto',
          ),
        )
        .replaceAll(
          '{logo}',
          context.tr(
            logo == null
                ? 'partnerMedia.a11y.noLogo'
                : 'partnerMedia.a11y.yourLogo',
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('partnerMedia.preview')),
        LayoutBuilder(
          builder: (context, c) {
            final preview = PartnerBandPreview(
              key: const Key('partner-media-preview'),
              side: widget.side,
              name: _bandName,
              label: label,
              ownPhoto: photo,
              logo: partnerLogoPlate(logo),
              forceSize: _wide ? kPartnerWidePreviewWindow : null,
            );
            if (!_wide) return preview;
            // 840+: the wide home's own banner, laid out as on a 1280 wide
            // screen (220 tall, text column unwrapped), scaled to the column.
            return FittedBox(
              key: const Key('partner-media-preview-wide-fit'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(width: kPartnerWidePreviewWidth, child: preview),
            );
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr(
            widget.side == 'trainer'
                ? 'partnerMedia.onlyYouSelf'
                : 'partnerMedia.onlyYouTeam',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _card(BuildContext context, String kind) {
    final logo = kind == 'logo';
    final title = context.tr(logo ? 'partnerMedia.logo' : 'partnerMedia.hero');
    final o = _o;
    final live = o?.live(kind);
    final down = o?.takedown(kind);
    final offline = _phase == _Phase.offline;
    final loading = _phase == _Phase.loading;
    final uploading = _uploadKind == kind;
    final error = _cardError[kind];
    final scheme = Theme.of(context).colorScheme;

    Widget thumb() {
      final saved = logo ? null : _saved?.photo;
      final savedLogo = logo ? _saved?.logo : null;
      if (uploading && _uploadThumb != null) {
        return _thumbBox(
          Image.memory(
            _uploadThumb!,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
          logo,
        );
      }
      if (logo) {
        if (savedLogo != null && (live != null || offline)) {
          return Semantics(
            label: context.tr('partnerMedia.a11y.currentLogo'),
            image: true,
            child: partnerLogoPlate(savedLogo)!,
          );
        }
        // An empty, dashed 40 x 40 plate outline (spec §41.3).
        return ExcludeSemantics(
          child: CustomPaint(
            key: Key('partner-media-$kind-empty-plate'),
            size: const Size.square(FFTokens.logoPlateHeight),
            painter: DashedPlatePainter(color: scheme.outline),
          ),
        );
      }
      if (saved != null && (live != null || offline)) {
        return Semantics(
          label: context.tr('partnerMedia.a11y.currentPhoto'),
          image: true,
          child: _thumbBox(
            Image(
              image: saved.provider,
              fit: BoxFit.cover,
              alignment: saved.focal,
              excludeFromSemantics: true,
            ),
            false,
          ),
        );
      }
      return ExcludeSemantics(
        child: _thumbBox(
          Image.asset(switch (widget.side) {
            'gym' => FFHeroPhoto.owner.asset,
            'trainer' => FFHeroPhoto.trainer.asset,
            _ => FFHeroPhoto.vendor.asset,
          }, fit: BoxFit.cover),
          false,
        ),
      );
    }

    final lines = <String>[];
    final actions = <Widget>[];
    Widget? alert;
    final canAct = _phase == _Phase.ready && !uploading && _removing == null;
    String uploadLabel(bool fresh) => context.tr(
      logo
          ? (fresh ? 'partnerMedia.uploadNewLogo' : 'partnerMedia.uploadLogo')
          : (fresh ? 'partnerMedia.uploadNew' : 'partnerMedia.upload'),
    );
    final offlineHint = offline ? context.tr('partnerMedia.offline') : null;

    if (loading) {
      return FFCard(
        key: Key('partner-media-$kind-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                FFSkeleton(width: logo ? 40 : 96, height: logo ? 40 : 64),
                const SizedBox(width: FFTokens.spacingMd),
                const Expanded(
                  child: Column(
                    children: [
                      FFSkeletonLine(),
                      SizedBox(height: FFTokens.spacingSm),
                      FFSkeletonLine(widthFactor: 0.6),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (uploading) {
      final p = _progress;
      lines.add(
        p == null || p.preparing
            ? context.tr('partnerMedia.sheet.preparing')
            : context
                  .tr('partnerMedia.sheet.uploading')
                  .replaceAll('{n}', '${(p.sent * 100).round()}'),
      );
    } else if (live != null ||
        (offline && (logo ? _saved?.logo : _saved?.photo) != null)) {
      lines.add(context.tr('partnerMedia.live'));
      if (live?.createdAt case final at?) {
        final d = formatDate(at, locale: _lang);
        lines.add(
          live!.setByFitflex
              ? context
                    .tr('partnerMedia.addedByFitflex')
                    .replaceAll('{date}', d)
              : context.tr('partnerMedia.addedOn').replaceAll('{date}', d),
        );
      }
      if (live != null && !logo && live.bright) {
        lines.add(context.tr('partnerMedia.bright'));
      }
      actions.addAll([
        _action(
          Key('partner-media-$kind-replace'),
          context.tr('partnerMedia.replace'),
          FFButtonVariant.secondary,
          canAct ? () => _start(kind) : null,
          offlineHint,
        ),
        _action(
          Key('partner-media-$kind-remove'),
          context.tr('partnerMedia.remove'),
          FFButtonVariant.ghost,
          canAct && live != null ? () => _remove(live) : null,
          offlineHint,
          loading: _removing == kind,
          danger: true,
        ),
      ]);
    } else if (down != null) {
      final reasonKey = 'partnerMedia.reason.${down.takedownReason ?? 'other'}';
      final reason = context.tr(reasonKey) == reasonKey
          ? context.tr('partnerMedia.reason.other')
          : context.tr(reasonKey);
      final message = [
        context.tr(
          logo ? 'partnerMedia.takenDownLogo' : 'partnerMedia.takenDownHero',
        ),
        context
            .tr('partnerMedia.takenDownReason')
            .replaceAll('{reason}', reason),
        if (down.takedownNote != null)
          context
              .tr('partnerMedia.takenDownNote')
              .replaceAll('{note}', down.takedownNote!),
        context.tr(
          logo
              ? 'partnerMedia.takenDownNextLogo'
              : 'partnerMedia.takenDownNext',
        ),
      ].join('\n');
      // One readable node with the whole text (reason and note), announced
      // when the page opens (spec §41.5).
      alert = Semantics(
        key: Key('partner-media-$kind-taken-down-semantics'),
        container: true,
        liveRegion: true,
        label: message,
        excludeSemantics: true,
        child: FFAlert(
          key: Key('partner-media-$kind-taken-down'),
          tone: FFAlertTone.error,
          message: message,
        ),
      );
      actions.add(
        _action(
          Key('partner-media-$kind-upload'),
          uploadLabel(true),
          FFButtonVariant.primary,
          canAct ? () => _start(kind) : null,
          offlineHint,
        ),
      );
    } else {
      lines.add(
        context.tr(logo ? 'partnerMedia.noLogo' : 'partnerMedia.default'),
      );
      actions.add(
        _action(
          Key('partner-media-$kind-upload'),
          uploadLabel(false),
          FFButtonVariant.primary,
          canAct ? () => _start(kind) : null,
          offlineHint,
        ),
      );
    }

    return FFCard(
      key: Key('partner-media-$kind-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (alert != null) ...[
            alert,
            const SizedBox(height: FFTokens.spacingSm),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                thumb(),
                const SizedBox(width: FFTokens.spacingMd),
                Expanded(
                  child: Semantics(
                    container: true,
                    child: Column(
                      key: Key('partner-media-$kind-status'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final l in lines) Text(l)],
                    ),
                  ),
                ),
              ],
            ),
          if (uploading && _progress != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ListenableBuilder(
              listenable: _progress!,
              builder: (context, _) => LinearProgressIndicator(
                value: _progress!.preparing ? null : _progress!.sent,
              ),
            ),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingSm,
            children: actions,
          ),
          if (error != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                key: Key('partner-media-$kind-error'),
                style: TextStyle(color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumbBox(Widget child, bool logo) => ClipRRect(
    borderRadius: BorderRadius.circular(FFTokens.radiusSm),
    child: SizedBox(
      width: logo ? 40 : 96,
      height: logo ? 40 : 64,
      child: child,
    ),
  );

  Widget _action(
    Key key,
    String label,
    FFButtonVariant variant,
    VoidCallback? onPressed,
    String? hint, {
    bool loading = false,
    bool danger = false,
  }) {
    final b = FFButton(
      key: key,
      label: label,
      variant: variant,
      maxLines: 3,
      loading: loading,
      onPressed: onPressed,
      // Error-tone label in light and dark (spec §41.3), set on the button.
      foregroundColor: danger ? Theme.of(context).colorScheme.error : null,
    );
    return hint == null ? b : Semantics(hint: hint, child: b);
  }

  Widget _rulesCard(BuildContext context) {
    const rules = [
      'partnerMedia.rules.own',
      'partnerMedia.rules.people',
      'partnerMedia.rules.brands',
      'partnerMedia.rules.text',
      'partnerMedia.rules.suitable',
      'partnerMedia.rules.size',
    ];
    return FFCard(
      key: const Key('partner-media-rules'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.tr('partnerMedia.rules.title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: Text('•  ')),
                  Expanded(child: Text(context.tr(r))),
                ],
              ),
            ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(context.tr('partnerMedia.rules.logo')),
        ],
      ),
    );
  }
}

/// The wide preview is laid out as the home banner on a window this size
/// (spec §41.2: what the partner's wide home shows).
const Size kPartnerWidePreviewWindow = Size(1280, 800);

/// The home's banner width on that window (24px page padding each side).
const double kPartnerWidePreviewWidth = 1232;

/// A dashed rounded square: the empty logo plate (spec §41.3).
class DashedPlatePainter extends CustomPainter {
  const DashedPlatePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(FFTokens.radiusSm),
        ),
      );
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedPlatePainter old) => old.color != color;
}
