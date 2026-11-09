// Vendor tools · S8 test support: a fake camera (a code stream, states and
// a torch) and the S8 seeds. Nothing talks to a real server or camera.
import 'dart:async';

import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FakeScanCamera implements VendorScanCamera {
  FakeScanCamera({
    VendorCameraStatus startsAs = VendorCameraStatus.active,
    bool? torch,
  }) : _startsAs = startsAs,
       _torch = ValueNotifier(torch);

  final VendorCameraStatus _startsAs;
  final _status = ValueNotifier(VendorCameraStatus.starting);
  final ValueNotifier<bool?> _torch;
  final _codes = StreamController<String>.broadcast();
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  @override
  bool running = false;

  /// The camera "sees" [raw].
  void see(String raw) => _codes.add(raw);

  @override
  ValueListenable<VendorCameraStatus> get status => _status;
  @override
  ValueListenable<bool?> get torch => _torch;
  @override
  Stream<String> get codes => _codes.stream;
  @override
  Widget preview() =>
      const ColoredBox(key: Key('fake-camera-preview'), color: Colors.black);
  @override
  Future<void> start() async {
    starts += 1;
    running = _startsAs == VendorCameraStatus.active;
    _status.value = _startsAs;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    running = false;
  }

  @override
  Future<void> toggleTorch() async {
    if (_torch.value != null) _torch.value = !_torch.value!;
  }

  @override
  void dispose() {
    disposed = true;
    running = false;
  }
}

/// Every panel in the test uses [camera] (the last one made is kept).
class FakeCameras {
  FakeCameras({this.startsAs = VendorCameraStatus.active, this.torch});
  final VendorCameraStatus startsAs;
  final bool? torch;
  final made = <FakeScanCamera>[];
  FakeScanCamera get last => made.last;

  void install() {
    VendorScanPanel.debugInsecure = false;
    VendorScanPanel.debugCameraFactory = () {
      final c = FakeScanCamera(startsAs: startsAs, torch: torch);
      made.add(c);
      return c;
    };
  }

  static void uninstall() {
    VendorScanPanel.debugCameraFactory = null;
    VendorScanPanel.debugInsecure = null;
  }
}

/// Options with barcodes on (and the slices it needs).
Map<String, dynamic> barcodeTools({
  bool barcodes = true,
  bool walkInSales = true,
  bool purchases = true,
}) => {
  'stockLedger': true,
  'canSeeCost': true,
  'walkInSales': walkInSales,
  'purchases': purchases,
  'barcodes': barcodes,
};
