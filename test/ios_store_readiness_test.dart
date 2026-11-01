import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// What App Store review reads from the iOS project. The prompts must describe
// what the iPhone build really does, so these move with the code.

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final en = File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync();
  final sw = File('ios/Runner/sw.lproj/InfoPlist.strings').readAsStringSync();

  test('the home screen says FitFlex', () {
    for (final key in ['CFBundleDisplayName', 'CFBundleName']) {
      expect(
        RegExp('<key>$key</key>\\s*<string>FitFlex</string>').hasMatch(plist),
        isTrue,
        reason: key,
      );
    }
  });

  test('no background location: iPhone has no run recording', () {
    // Both come back together if GeolocatorGpsSource is enabled on iOS.
    final gps = File(
      'lib/shared/activity/providers/geolocator_gps_source.dart',
    ).readAsStringSync();
    expect(gps, contains('defaultTargetPlatform == TargetPlatform.android'));
    expect(plist, isNot(contains('NSLocationAlways')));
    expect(plist, isNot(contains('UIBackgroundModes')));
    expect(en, isNot(contains('NSLocationAlways')));
    expect(sw, isNot(contains('NSLocationAlways')));
  });

  test('the location prompt does not promise runs on iPhone', () {
    for (final text in [plist, en]) {
      expect(text, isNot(contains('record your runs')));
      expect(text, contains('pickup gyms'));
    }
    expect(sw, isNot(contains('kurekodi mbio')));
  });

  test('only keys the app needs are declared', () {
    expect(plist, isNot(contains('NSUserTrackingUsageDescription')));
    expect(plist, isNot(contains('NSMicrophoneUsageDescription')));
    expect(plist, contains('NSPhotoLibraryAddUsageDescription'));
  });
}
