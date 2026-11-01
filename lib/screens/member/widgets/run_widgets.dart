import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/activity/run_metrics.dart';
import '../../../shared/activity/run_recorder.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

/// The route on a map. With [follow], it keeps the latest point in view
/// (while recording); otherwise it fits the whole route.
class RunMap extends StatefulWidget {
  const RunMap({
    super.key,
    required this.segments,
    this.follow = false,
    this.height = 240,
  });

  final List<List<TrackPoint>> segments;
  final bool follow;
  final double height;

  @override
  State<RunMap> createState() => _RunMapState();
}

class _RunMapState extends State<RunMap> {
  final _ctrl = MapController();
  bool _ready = false;

  List<LatLng> get _all => [
    for (final s in widget.segments)
      for (final p in s) LatLng(p.lat, p.lng),
  ];

  @override
  void didUpdateWidget(covariant RunMap old) {
    super.didUpdateWidget(old);
    final pts = _all;
    if (widget.follow && _ready && pts.isNotEmpty) {
      _ctrl.move(pts.last, _ctrl.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Route and position dot sit on light map tiles in both themes, so use
    // the fixed map-pin green (>= 5:1 on the tiles), not the theme primary.
    const color = FFTokens.mapPin;
    final pts = _all;
    final fit = !widget.follow && pts.length >= 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      child: SizedBox(
        height: widget.height,
        child: pts.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(child: Text(context.tr('run.waitingGps'))),
              )
            : FlutterMap(
                mapController: _ctrl,
                options: MapOptions(
                  initialCenter: pts.last,
                  initialZoom: 16,
                  initialCameraFit: fit
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(pts),
                          padding: const EdgeInsets.all(28),
                        )
                      : null,
                  onMapReady: () => _ready = true,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.fitflex.mobile',
                  ),
                  PolylineLayer(
                    polylines: [
                      for (final s in widget.segments)
                        if (s.length >= 2)
                          Polyline(
                            points: [for (final p in s) LatLng(p.lat, p.lng)],
                            strokeWidth: 5,
                            color: color,
                            borderStrokeWidth: 1.5,
                            borderColor: FFTokens.mapPinHalo,
                          ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pts.last,
                        width: 18,
                        height: 18,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: FFTokens.mapPinHalo,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// "5.24 km" — runs show hundredths.
String formatRunKm(double km) => '${km.toStringAsFixed(2)} km';

/// One number with its label, for the run screens.
class RunStat extends StatelessWidget {
  const RunStat({
    super.key,
    required this.value,
    required this.label,
    this.big = false,
  });

  final String value;
  final String label;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style:
                (big
                        ? theme.textTheme.displaySmall
                        : theme.textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Distance, time, pace, speed, climb and (estimated) calories.
class RunSummaryGrid extends StatelessWidget {
  const RunSummaryGrid({
    super.key,
    required this.distanceKm,
    required this.seconds,
    required this.elevationGainM,
    this.calories,
    this.showCalories = true,
  });

  final double distanceKm;
  final int seconds;
  final num elevationGainM;
  final int? calories;
  final bool showCalories;

  @override
  Widget build(BuildContext context) {
    final pace = distanceKm < 0.01 ? null : (seconds / distanceKm).round();
    final kmh = seconds <= 0 ? 0.0 : distanceKm / (seconds / 3600);
    final cells = [
      RunStat(
        value: formatRunKm(distanceKm),
        label: context.tr('run.distance'),
      ),
      RunStat(value: formatDuration(seconds), label: context.tr('run.time')),
      RunStat(value: formatPace(pace), label: context.tr('run.pace')),
      RunStat(
        value: '${kmh.toStringAsFixed(1)} km/h',
        label: context.tr('run.speed'),
      ),
      RunStat(
        value: '${elevationGainM.round()} m',
        label: context.tr('run.climb'),
      ),
      if (showCalories)
        RunStat(
          value: calories == null ? '—' : '$calories kcal',
          label: context.tr(
            calories == null
                ? 'run.caloriesNeedWeight'
                : 'run.caloriesEstimated',
          ),
        ),
    ];
    return FFCard(
      child: Wrap(
        runSpacing: FFTokens.spacingMd,
        children: [
          for (final c in cells)
            FractionallySizedBox(
              widthFactor: 1 / 3,
              child: Padding(
                padding: const EdgeInsets.only(right: FFTokens.spacingSm),
                child: c,
              ),
            ),
        ],
      ),
    );
  }
}

/// Time for each whole km.
class RunSplits extends StatelessWidget {
  const RunSplits({super.key, required this.splits});

  final List<int> splits;

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final fastest = splits.reduce((a, b) => a < b ? a : b);
    return FFCard(
      key: const Key('run-splits'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('run.splits'), style: theme.textTheme.titleSmall),
          const SizedBox(height: FFTokens.spacingSm),
          for (final (i, s) in splits.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      'km ${i + 1}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: fastest / s,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Flexible(
                    flex: 2,
                    child: Text(
                      '${formatPace(s)} /km',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: s == fastest ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Record a run" on the Activity tab, or "Run in progress" while one is.
/// Hidden where recording isn't offered.
class RecordRunButton extends StatelessWidget {
  const RecordRunButton({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.getInheritedWidgetOfExactType<AppScope>()?.runRecorder;
    if (r == null || !r.supported) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        final live = r.state != RunState.idle;
        return Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingMd),
          child: FilledButton.icon(
            key: const Key('record-run-open'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => context.go(AppRoutes.memberRecordRun),
            icon: Icon(live ? Icons.fiber_manual_record : Icons.directions_run),
            label: Text(
              live
                  ? context
                        .tr('run.inProgress')
                        .replaceAll('{km}', formatRunKm(r.metrics.distanceKm))
                  : context.tr('run.open'),
            ),
          ),
        );
      },
    );
  }
}
