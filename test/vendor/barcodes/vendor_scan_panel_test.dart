// Vendor tools · S8 §4: the scan panel with a fake camera — camera states,
// torch, pause, held by a sheet, dispose, Type code, remembered failure,
// insecure page, semantics and Swahili layout.
import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_controller.dart';
import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_api.dart';
import 'scan_support.dart';

class _Host extends StatefulWidget {
  const _Host({
    required this.controller,
    required this.seen,
    this.continuous = true,
  });
  final VendorScanController controller;
  final List<String> seen;
  final bool continuous;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool open = true;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: open
        ? VendorScanPanel(
            controller: widget.controller,
            continuous: widget.continuous,
            memoryScope: 'v1',
            onClose: () => setState(() => open = false),
            onCode: (raw, {required typed}) async {
              widget.seen.add('${typed ? 'typed' : 'camera'}:$raw');
              return true;
            },
          )
        : const Text('CLOSED'),
  );
}

Future<(PageHost, List<String>, VendorScanController)> pumpPanel(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  bool continuous = true,
  Size size = const Size(400, 800),
}) async {
  final seen = <String>[];
  final controller = VendorScanController(index: ProductCodeIndex.empty);
  addTearDown(controller.dispose);
  final host = await pumpPage(
    tester,
    api,
    _Host(controller: controller, seen: seen, continuous: continuous),
    lang: lang,
    size: size,
  );
  return (host, seen, controller);
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(FakeCameras.uninstall);

  apiTest('starts the camera, passes codes on, Stop turns it off', (
    tester,
    api,
  ) async {
    final cams = FakeCameras()..install();
    final (_, seen, _) = await pumpPanel(tester, api);
    expect(cams.last.starts, 1);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    cams.last.see('6201234567893');
    await tester.pumpAndSettle();
    expect(seen, ['camera:6201234567893']);
    await tester.tap(find.byKey(const Key('scan-close')));
    await tester.pumpAndSettle();
    expect(find.text('CLOSED'), findsOneWidget);
    expect(cams.last.disposed, isTrue);
    expect(cams.last.running, isFalse);
  });

  apiTest('torch only when the camera has one, and it toggles', (
    tester,
    api,
  ) async {
    FakeCameras().install();
    await pumpPanel(tester, api);
    expect(find.byKey(const Key('scan-torch')), findsNothing);
    FakeCameras.uninstall();
    await tester.pumpWidget(const SizedBox());
    final cams = FakeCameras(torch: false)..install();
    final (host, _, _) = await pumpPanel(tester, api);
    expect(find.byTooltip(host.tr('vendor.scan.torchOn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-torch')));
    await tester.pumpAndSettle();
    expect(cams.last.torch.value, isTrue);
    expect(find.byTooltip(host.tr('vendor.scan.torchOff')), findsOneWidget);
  });

  apiTest('Pause stops the camera (codes ignored); Resume starts it', (
    tester,
    api,
  ) async {
    final cams = FakeCameras()..install();
    final (host, seen, _) = await pumpPanel(tester, api);
    await tester.tap(find.byKey(const Key('scan-pause')));
    await tester.pumpAndSettle();
    expect(cams.last.running, isFalse);
    expect(find.byKey(const Key('scan-paused')), findsOneWidget);
    cams.last.see('6201234567893');
    await tester.pumpAndSettle();
    expect(seen, isEmpty);
    expect(find.text(host.tr('vendor.scan.resume')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-pause')));
    await tester.pumpAndSettle();
    expect(cams.last.running, isTrue);
  });

  apiTest('a sheet held over it stops the camera until released', (
    tester,
    api,
  ) async {
    final cams = FakeCameras()..install();
    final (_, _, controller) = await pumpPanel(tester, api);
    controller.hold();
    await tester.pumpAndSettle();
    expect(cams.last.running, isFalse);
    controller.release();
    await tester.pumpAndSettle();
    expect(cams.last.running, isTrue);
  });

  apiTest('background stops the camera; resumed starts it', (
    tester,
    api,
  ) async {
    final cams = FakeCameras()..install();
    await pumpPanel(tester, api);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(cams.last.running, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cams.last.running, isTrue);
  });

  for (final (status, key, retry) in [
    (VendorCameraStatus.denied, 'vendor.scan.camera.denied', true),
    (VendorCameraStatus.unsupported, 'vendor.scan.camera.unsupported', false),
    (VendorCameraStatus.error, 'vendor.scan.camera.error', true),
  ]) {
    apiTest(
      'camera $status: its words, Try again ${retry ? 'shown' : 'hidden'}, Type code works',
      (tester, api) async {
        FakeCameras(startsAs: status).install();
        final (host, seen, _) = await pumpPanel(tester, api);
        expect(find.text(host.tr(key)), findsOneWidget);
        expect(
          find.byKey(const Key('scan-retry')),
          retry ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.byKey(const Key('scan-camera-type')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('scan-type-field')),
          '6201234567893',
        );
        await tester.tap(find.byKey(const Key('scan-find')));
        await tester.pumpAndSettle();
        expect(seen, ['typed:6201234567893']);
        // The field clears and keeps focus for the next code.
        expect(textOf(tester, find.byKey(const Key('scan-type-field'))), '');
      },
    );
  }

  apiTest(
    'after a failure the next panel opens on Type code with "Try the camera"',
    (tester, api) async {
      FakeCameras(startsAs: VendorCameraStatus.denied).install();
      await pumpPanel(tester, api);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(VendorScanMemory.key('v1')), isTrue);
      await tester.pumpWidget(const SizedBox());
      final cams = FakeCameras()..install();
      final (host, _, _) = await pumpPanel(tester, api);
      expect(cams.made, isEmpty, reason: 'never asks for the camera on open');
      expect(find.byKey(const Key('scan-type-field')), findsOneWidget);
      await tester.tap(find.text(host.tr('vendor.scan.tryCamera')));
      await tester.pumpAndSettle();
      expect(cams.last.running, isTrue);
      expect(prefs.getBool(VendorScanMemory.key('v1')), isNull);
    },
  );

  apiTest('insecure (http) page: the https message and Type code only', (
    tester,
    api,
  ) async {
    final cams = FakeCameras()..install();
    VendorScanPanel.debugInsecure = true;
    final (host, _, _) = await pumpPanel(tester, api);
    expect(cams.made, isEmpty);
    expect(find.text(host.tr('vendor.scan.camera.insecure')), findsOneWidget);
    expect(find.byKey(const Key('scan-type-field')), findsOneWidget);
    expect(find.byKey(const Key('scan-try-camera')), findsNothing);
  });

  apiTest('semantics labels and 48dp targets', (tester, api) async {
    FakeCameras(torch: false).install();
    final handle = tester.ensureSemantics();
    final (host, _, _) = await pumpPanel(tester, api);
    expect(
      find.bySemanticsLabel(host.tr('vendor.scan.preview')),
      findsOneWidget,
    );
    for (final k in ['scan-torch', 'scan-pause', 'scan-close', 'scan-type']) {
      final size = tester.getSize(find.byKey(Key(k)));
      expect(size.height, greaterThanOrEqualTo(48), reason: k);
      expect(size.width, greaterThanOrEqualTo(48), reason: k);
    }
    expect(find.byTooltip(host.tr('vendor.scan.close')), findsOneWidget);
    handle.dispose();
  });

  apiTest('Swahili at 360: Pause is an icon with its label as tooltip', (
    tester,
    api,
  ) async {
    FakeCameras().install();
    final (host, _, _) = await pumpPanel(
      tester,
      api,
      lang: 'sw',
      size: const Size(360, 740),
    );
    expect(find.byTooltip(host.tr('vendor.scan.pause')), findsOneWidget);
    expect(find.text('Sitisha kuskani'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  apiTest('single shot: no Pause', (tester, api) async {
    FakeCameras().install();
    await pumpPanel(tester, api, continuous: false);
    expect(find.byKey(const Key('scan-pause')), findsNothing);
  });
}
