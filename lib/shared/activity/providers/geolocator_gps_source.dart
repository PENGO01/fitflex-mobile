import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../gps_source.dart';
import '../run_metrics.dart';

/// GPS through geolocator. On Android it runs as a foreground service with
/// an ongoing notification, so a run keeps recording with the screen off.
/// Only "while in use" permission is needed: the member starts the run.
/// Not on iOS: giving it runs means adding `UIBackgroundModes` location and
/// the Always purpose text back to Info.plist.
class GeolocatorGpsSource implements GpsSource {
  const GeolocatorGpsSource();

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<GpsAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return GpsAccess.serviceOff;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return switch (p) {
      LocationPermission.always ||
      LocationPermission.whileInUse => GpsAccess.granted,
      LocationPermission.deniedForever => GpsAccess.deniedForever,
      _ => GpsAccess.denied,
    };
  }

  @override
  Stream<TrackPoint> track({
    required String notificationTitle,
    required String notificationText,
  }) =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
          intervalDuration: const Duration(seconds: 2),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: notificationTitle,
            notificationText: notificationText,
            notificationChannelName: 'Run recording',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).map(
        (p) => TrackPoint(
          p.latitude,
          p.longitude,
          p.altitude == 0 && p.altitudeAccuracy == 0 ? null : p.altitude,
          p.timestamp,
          p.accuracy,
        ),
      );

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
