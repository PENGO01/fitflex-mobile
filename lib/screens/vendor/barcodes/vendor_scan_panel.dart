// Vendor tools · S8: the scan panel (spec §4). One docked panel for the
// POS, Receive stock and counting, and a single-shot sheet for the Products
// tab and the product form.
//
// - The camera only starts from a user tap (the panel is opened by one) and
//   stops when the panel closes, is paused, a sheet is held over it, or the
//   app goes to the background.
// - Type code is always there: a typed code, Enter, or a USB / Bluetooth
//   keyboard scanner goes through the same handler as the camera.
// - Camera errors use the owner scan page's layout (icon, words, Try again,
//   a way out) with vendor words; the owner and member scan pages are not
//   touched.
// - Once the camera failed on this device, the panel opens on Type code with
//   "Try the camera".
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';
import 'barcode_rules.dart';
import 'vendor_scan_controller.dart';

/// What the camera is doing.
enum VendorCameraStatus { starting, active, denied, unsupported, error }

/// The camera behind the panel. [MobileVendorScanCamera] in the app; tests
/// give a fake that emits codes and states.
abstract class VendorScanCamera {
  ValueListenable<VendorCameraStatus> get status;

  /// Null when the camera has no torch (usually on Flutter web); else
  /// whether it is on.
  ValueListenable<bool?> get torch;

  /// Raw values of detected codes.
  Stream<String> get codes;

  Widget preview();
  Future<void> start();
  Future<void> stop();
  Future<void> toggleTorch();
  void dispose();
}

/// The camera formats S8 reads (§4.3): fewer formats, faster detection.
const vendorScanFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.itf,
  BarcodeFormat.qrCode,
];

/// mobile_scanner's camera.
class MobileVendorScanCamera implements VendorScanCamera {
  MobileVendorScanCamera()
    : _ctl = MobileScannerController(
        autoStart: false,
        formats: vendorScanFormats,
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 250,
      ) {
    _ctl.addListener(_sync);
    _sub = _ctl.barcodes.listen((capture) {
      for (final b in capture.barcodes) {
        final raw = b.rawValue;
        if (raw != null && raw.isNotEmpty) {
          _codes.add(raw);
          break;
        }
      }
    });
  }

  final MobileScannerController _ctl;
  late final StreamSubscription<BarcodeCapture> _sub;
  final _codes = StreamController<String>.broadcast();
  final _status = ValueNotifier(VendorCameraStatus.starting);
  final _torch = ValueNotifier<bool?>(null);

  @override
  ValueListenable<VendorCameraStatus> get status => _status;
  @override
  ValueListenable<bool?> get torch => _torch;
  @override
  Stream<String> get codes => _codes.stream;

  void _sync() {
    final v = _ctl.value;
    final error = v.error;
    if (error != null) {
      _status.value = switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied => VendorCameraStatus.denied,
        MobileScannerErrorCode.unsupported => VendorCameraStatus.unsupported,
        _ => VendorCameraStatus.error,
      };
    } else if (v.isRunning) {
      _status.value = VendorCameraStatus.active;
    }
    _torch.value = switch (v.torchState) {
      TorchState.unavailable => null,
      TorchState.on => true,
      _ => false,
    };
  }

  @override
  Widget preview() => MobileScanner(
    controller: _ctl,
    fit: BoxFit.cover,
    // The panel shows its own error view (from [status]).
    errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
    placeholderBuilder: (_, _) => const ColoredBox(color: Colors.black),
  );

  @override
  Future<void> start() async {
    _status.value = VendorCameraStatus.starting;
    try {
      await _ctl.start();
      _sync();
    } catch (_) {
      // Not a MobileScannerException (e.g. no plugin): the error view.
      _status.value = VendorCameraStatus.error;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _ctl.stop();
    } catch (_) {}
  }

  @override
  Future<void> toggleTorch() async {
    try {
      await _ctl.toggleTorch();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctl.removeListener(_sync);
    unawaited(_sub.cancel());
    unawaited(_codes.close());
    unawaited(_ctl.dispose());
    _status.dispose();
    _torch.dispose();
  }
}

/// The page is served over plain http (not localhost): browsers give no
/// camera there.
bool vendorScanPageInsecure() =>
    kIsWeb &&
    Uri.base.scheme != 'https' &&
    !const {'localhost', '127.0.0.1'}.contains(Uri.base.host);

/// The vendor the signed-in person works for (the "camera failed here"
/// memory is per vendor, per device).
String vendorScanScope(BuildContext context) {
  final user = AppScope.of(context).auth.user;
  final type = user?['userType']?.toString();
  final key = type == 'vendor_staff' ? 'vendorId' : 'id';
  final id = user?[key]?.toString();
  return (id == null || id.isEmpty) ? 'default' : id;
}

/// The camera failed on this device before (per vendor): the panel opens on
/// Type code.
class VendorScanMemory {
  static String key(String scope) => 'vendor_scan_camera_failed.$scope';

  static Future<bool> failed(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key(scope)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> remember(String scope, bool failed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      failed
          ? await prefs.setBool(key(scope), true)
          : await prefs.remove(key(scope));
    } catch (_) {}
  }
}

/// The handler a screen gives the panel. Resolves true when the code was
/// matched and used (the guide flashes green).
typedef VendorScanHandler =
    Future<bool> Function(String raw, {required bool typed});

class VendorScanPanel extends StatefulWidget {
  const VendorScanPanel({
    super.key,
    required this.controller,
    required this.onCode,
    required this.onClose,
    this.continuous = true,
    this.result,
    this.memoryScope = 'default',
    this.cameraFactory,
    this.insecure,
    this.viewfinderHeight,
    this.startTyping = false,
  });

  final VendorScanController controller;
  final VendorScanHandler onCode;
  final VoidCallback onClose;

  /// Continuous (POS, Receive stock, counting): Pause and the result row.
  /// Single shot (sheet): neither.
  final bool continuous;

  /// The screen's result row (continuous mode).
  final Widget? result;

  /// Where "the camera failed here" is remembered (the vendor id).
  final String memoryScope;

  /// The camera; [MobileVendorScanCamera] when null.
  final VendorScanCamera Function()? cameraFactory;

  /// Overrides the http check (tests).
  final bool? insecure;

  /// Overrides the viewfinder height.
  final double? viewfinderHeight;

  /// Open on Type code (e.g. "Search by name" closed it).
  final bool startTyping;

  /// Tests: the camera every panel uses when none is given.
  @visibleForTesting
  static VendorScanCamera Function()? debugCameraFactory;

  /// Tests: the http check every panel uses when none is given.
  @visibleForTesting
  static bool? debugInsecure;

  @override
  State<VendorScanPanel> createState() => VendorScanPanelState();
}

class VendorScanPanelState extends State<VendorScanPanel>
    with WidgetsBindingObserver {
  VendorScanCamera? _camera;
  StreamSubscription<String>? _codes;
  bool _typing = false;
  bool _userPaused = false;
  bool _held = false;
  bool _background = false;
  bool _flash = false;
  Timer? _flashTimer;
  bool _rememberedFailure = false;
  final _typed = TextEditingController();
  final _typedFocus = FocusNode();

  bool get _insecure =>
      widget.insecure ??
      VendorScanPanel.debugInsecure ??
      vendorScanPageInsecure();

  /// The camera is meant to be running now.
  bool get _wantsCamera =>
      !_typing && !_userPaused && !_held && !_background && !_insecure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onController);
    _typing = widget.startTyping || _insecure;
    if (!_typing) {
      VendorScanMemory.failed(widget.memoryScope).then((failed) {
        if (!mounted) return;
        if (failed) {
          setState(() {
            _typing = true;
            _rememberedFailure = true;
          });
        } else {
          _syncCamera();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onController);
    _flashTimer?.cancel();
    _dropCamera();
    _typed.dispose();
    _typedFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state != AppLifecycleState.resumed;
    if (background == _background) return;
    _background = background;
    _syncCamera();
    if (mounted) setState(() {});
  }

  void _onController() {
    final held = widget.controller.held;
    if (held != _held) {
      _held = held;
      _syncCamera();
    }
    if (mounted) setState(() {});
  }

  /// Starts or stops the camera to match what the panel shows.
  void _syncCamera() {
    if (!mounted) return;
    if (!_wantsCamera) {
      unawaited(_camera?.stop());
      return;
    }
    var camera = _camera;
    if (camera == null) {
      camera =
          (widget.cameraFactory ??
          VendorScanPanel.debugCameraFactory ??
          MobileVendorScanCamera.new)();
      _camera = camera;
      camera.status.addListener(_onStatus);
      camera.torch.addListener(_redraw);
      _codes = camera.codes.listen((raw) => _submit(raw, typed: false));
    }
    unawaited(camera.start());
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _onStatus() {
    final s = _camera?.status.value;
    if (s == null) return;
    if (s == VendorCameraStatus.active) {
      unawaited(VendorScanMemory.remember(widget.memoryScope, false));
    } else if (s != VendorCameraStatus.starting) {
      unawaited(VendorScanMemory.remember(widget.memoryScope, true));
    }
    _redraw();
  }

  void _dropCamera() {
    final camera = _camera;
    if (camera == null) return;
    camera.status.removeListener(_onStatus);
    camera.torch.removeListener(_redraw);
    unawaited(_codes?.cancel());
    unawaited(camera.stop());
    camera.dispose();
    _camera = null;
    _codes = null;
  }

  Future<void> _submit(String raw, {required bool typed}) async {
    if (!mounted) return;
    // A paused or covered camera never sends codes on.
    if (!typed && !_wantsCamera) return;
    final ok = await widget.onCode(raw, typed: typed);
    if (!mounted) return;
    if (ok) {
      _flashTimer?.cancel();
      setState(() => _flash = true);
      _flashTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }

  void _find() {
    final text = _typed.text.trim();
    if (text.isEmpty) return;
    _typed.clear();
    _typedFocus.requestFocus();
    _submit(text, typed: true);
  }

  void _showTyping() {
    setState(() => _typing = true);
    _syncCamera();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _typedFocus.requestFocus(),
    );
  }

  void _tryCamera() {
    setState(() {
      _typing = false;
      _rememberedFailure = false;
    });
    _retry();
  }

  void _retry() {
    _dropCamera();
    _syncCamera();
    setState(() {});
  }

  void _togglePause() {
    setState(() => _userPaused = !_userPaused);
    _syncCamera();
    SemanticsService.sendAnnouncement(
      View.of(context),
      context.tr(_userPaused ? 'vendor.scan.paused' : 'vendor.scan.resume'),
      Directionality.of(context),
    );
  }

  /// Stops the camera now (the screen is about to close the panel).
  Future<void> stopCamera() async => _camera?.stop();

  double _height(BuildContext context) {
    final given = widget.viewfinderHeight;
    if (given != null) return given;
    final size = MediaQuery.sizeOf(context);
    if (!widget.continuous) return (size.height * 0.5).clamp(180.0, 420.0);
    if (size.width >= 900) return 280;
    return size.height < 640 ? 180 : 220;
  }

  @override
  Widget build(BuildContext context) {
    final height = _height(context);
    final controller = widget.controller;
    return Column(
      key: const Key('scan-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At 200% text the viewfinder keeps its height; the rest grows.
        SizedBox(
          height: _typing ? null : height,
          child: _typing ? _typeEntry() : _viewfinder(height),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        _controls(),
        if (controller.looking != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Row(
                key: const Key('scan-looking'),
                children: [
                  const FFSpinner(size: 16),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Text(
                      fillCode(
                        context.tr('vendor.scan.looking'),
                        controller.looking!,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (widget.continuous && widget.result != null) ...[
          const SizedBox(height: FFTokens.spacingXs),
          widget.result!,
        ],
      ],
    );
  }

  Widget _typeEntry() {
    final t = context.tr;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_insecure)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: FFAlert(
                key: const Key('scan-insecure'),
                message: t('vendor.scan.camera.insecure'),
                tone: FFAlertTone.info,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FFTextField(
                  key: const Key('scan-type-field'),
                  controller: _typed,
                  focusNode: _typedFocus,
                  label: t('vendor.scan.typeLabel'),
                  // No autocorrect, letters allowed.
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.search,
                  autofocus: true,
                  onFieldSubmitted: (_) => _find(),
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              FFButton(
                key: const Key('scan-find'),
                label: t('vendor.scan.find'),
                visualDensity: VisualDensity.standard,
                onPressed: _find,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewfinder(double height) {
    final t = context.tr;
    final camera = _camera;
    final status = camera?.status.value ?? VendorCameraStatus.starting;
    final error = switch (status) {
      VendorCameraStatus.denied ||
      VendorCameraStatus.unsupported ||
      VendorCameraStatus.error => status,
      _ => null,
    };
    if (error != null) {
      return VendorScanCameraError(
        status: error,
        onRetry: _retry,
        onType: _showTyping,
      );
    }
    final paused = _userPaused || _held || _background;
    final tones = FFToneTheme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final guide = BoxDecoration(
      border: Border.all(
        width: 2,
        color: _flash ? tones.success.fg : Colors.white70,
      ),
      borderRadius: BorderRadius.circular(FFTokens.radiusSm),
    );
    return Semantics(
      image: true,
      label: t('vendor.scan.preview'),
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (camera != null && !paused) camera.preview(),
              Center(
                child: LayoutBuilder(
                  builder: (context, box) => reduceMotion
                      ? Container(
                          key: const Key('scan-guide'),
                          width: box.maxWidth < 292 ? box.maxWidth - 32 : 260,
                          height: 120 > height - 72 ? height - 72 : 120,
                          decoration: guide,
                        )
                      : AnimatedContainer(
                          key: const Key('scan-guide'),
                          duration: const Duration(milliseconds: 150),
                          width: box.maxWidth < 292 ? box.maxWidth - 32 : 260,
                          height: 120 > height - 72 ? height - 72 : 120,
                          decoration: guide,
                        ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Padding(
                    padding: const EdgeInsets.all(FFTokens.spacingXs),
                    child: Text(
                      t('vendor.scan.hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              if (status == VendorCameraStatus.starting && !paused)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FFSpinner(color: Colors.white),
                      const SizedBox(height: FFTokens.spacingXs),
                      Text(
                        t('vendor.scan.starting'),
                        key: const Key('scan-starting'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              if (paused)
                ColoredBox(
                  key: const Key('scan-paused'),
                  color: Colors.black.withValues(alpha: 0.7),
                  child: Center(
                    child: Text(
                      t('vendor.scan.paused'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final t = context.tr;
    final torch = _typing ? null : _camera?.torch.value;
    final sw = FFLocaleScope.of(context).locale.languageCode == 'sw';
    final narrow = MediaQuery.sizeOf(context).width < 360;
    const square = Size(48, 48);
    final iconStyle = IconButton.styleFrom(
      minimumSize: square,
      visualDensity: VisualDensity.standard,
    );
    final pauseLabel = t(
      _userPaused ? 'vendor.scan.resume' : 'vendor.scan.pause',
    );
    return Wrap(
      spacing: FFTokens.spacingXs,
      runSpacing: FFTokens.spacingXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (torch != null)
          Semantics(
            toggled: torch,
            child: IconButton(
              key: const Key('scan-torch'),
              style: iconStyle,
              tooltip: t(
                torch ? 'vendor.scan.torchOff' : 'vendor.scan.torchOn',
              ),
              icon: Icon(torch ? Icons.flash_off : Icons.flash_on),
              onPressed: () => _camera?.toggleTorch(),
            ),
          ),
        if (_typing && !_insecure)
          FFButton(
            key: const Key('scan-try-camera'),
            label: t('vendor.scan.tryCamera'),
            icon: Icons.photo_camera_outlined,
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _tryCamera,
          )
        else if (!_typing)
          FFButton(
            key: const Key('scan-type'),
            label: t('vendor.scan.type'),
            icon: Icons.keyboard,
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _showTyping,
          ),
        if (widget.continuous && !_typing)
          sw || narrow
              ? IconButton(
                  key: const Key('scan-pause'),
                  style: iconStyle,
                  tooltip: pauseLabel,
                  icon: Icon(_userPaused ? Icons.play_arrow : Icons.pause),
                  onPressed: _togglePause,
                )
              : FFButton(
                  key: const Key('scan-pause'),
                  label: pauseLabel,
                  icon: _userPaused ? Icons.play_arrow : Icons.pause,
                  variant: FFButtonVariant.ghost,
                  visualDensity: VisualDensity.standard,
                  onPressed: _togglePause,
                ),
        IconButton(
          key: const Key('scan-close'),
          style: iconStyle,
          tooltip: t('vendor.scan.close'),
          icon: const Icon(Icons.close),
          onPressed: () {
            unawaited(_camera?.stop());
            widget.onClose();
          },
        ),
        if (_rememberedFailure)
          const SizedBox.shrink(key: Key('scan-remembered-failure')),
      ],
    );
  }
}

/// `{code}` filled in.
String fillCode(String template, String code) =>
    template.replaceAll('{code}', code);

/// The camera could not start: the owner scan page's layout with vendor
/// words, Try again (not when the device cannot scan at all) and Type code.
class VendorScanCameraError extends StatelessWidget {
  const VendorScanCameraError({
    super.key,
    required this.status,
    required this.onRetry,
    required this.onType,
  });

  final VendorCameraStatus status;
  final VoidCallback onRetry;
  final VoidCallback onType;

  static String messageKey(VendorCameraStatus status) => switch (status) {
    VendorCameraStatus.denied => 'vendor.scan.camera.denied',
    VendorCameraStatus.unsupported => 'vendor.scan.camera.unsupported',
    _ => 'vendor.scan.camera.error',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      key: const Key('scan-camera-error'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.no_photography_outlined,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context.tr(messageKey(status)),
                  key: const Key('scan-camera-error-text'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingXs,
                  children: [
                    if (status != VendorCameraStatus.unsupported)
                      FFButton(
                        key: const Key('scan-retry'),
                        label: context.tr('common.retry'),
                        icon: Icons.refresh,
                        visualDensity: VisualDensity.standard,
                        onPressed: onRetry,
                      ),
                    FFButton(
                      key: const Key('scan-camera-type'),
                      label: context.tr('vendor.scan.type'),
                      icon: Icons.keyboard,
                      variant: FFButtonVariant.secondary,
                      visualDensity: VisualDensity.standard,
                      onPressed: onType,
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
}

/// Opens the panel in a sheet and resolves with the first valid code
/// (Products tab, product form). FitFlex QR codes are refused in place.
Future<String?> scanOneCode(
  BuildContext context, {
  required String title,
  String memoryScope = 'default',
  VendorScanCamera Function()? cameraFactory,
  bool? insecure,
}) {
  final controller = VendorScanController(index: ProductCodeIndex.empty);
  return showFFSheet<String>(
    context,
    title: title,
    child: _SingleShot(
      controller: controller,
      memoryScope: memoryScope,
      cameraFactory: cameraFactory,
      insecure: insecure,
    ),
  ).whenComplete(controller.dispose);
}

class _SingleShot extends StatefulWidget {
  const _SingleShot({
    required this.controller,
    required this.memoryScope,
    this.cameraFactory,
    this.insecure,
  });

  final VendorScanController controller;
  final String memoryScope;
  final VendorScanCamera Function()? cameraFactory;
  final bool? insecure;

  @override
  State<_SingleShot> createState() => _SingleShotState();
}

class _SingleShotState extends State<_SingleShot> {
  bool _notProduct = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VendorScanPanel(
          controller: widget.controller,
          continuous: false,
          memoryScope: widget.memoryScope,
          cameraFactory: widget.cameraFactory,
          insecure: widget.insecure,
          onClose: () => Navigator.of(context).pop(),
          onCode: (raw, {required typed}) async {
            final code = raw.trim();
            if (code.isEmpty) return false;
            if (isNotProductCode(code)) {
              setState(() => _notProduct = true);
              return false;
            }
            Navigator.of(context).pop(code);
            return true;
          },
        ),
        if (_notProduct)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(
                key: const Key('scan-not-product'),
                message: context.tr('vendor.scan.notProduct'),
                tone: FFAlertTone.warning,
              ),
            ),
          ),
      ],
    );
  }
}
