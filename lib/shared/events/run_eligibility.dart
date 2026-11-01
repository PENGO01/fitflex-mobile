// Events S6 (spec §5.2, §10.2): the friendly pre-check for "Add a recorded
// run". The server decides; this only labels each run so a member does not
// tap one that is certain to be refused. It never blocks a run the server
// might accept: when unsure, a run is Available.
import '../activity/activity.dart';

/// The state chip of a run in the "Add a recorded run" list.
enum RunFit { available, short, outside, linked, notRecordedInApp }

/// The run window (D51): virtual = the event window, the run must start
/// inside; in-person = two hours before the start to twelve after the end.
({DateTime from, DateTime to}) runWindow({
  required bool isVirtual,
  required DateTime startsAt,
  required DateTime endsAt,
  DateTime? categoryStartsAt,
}) {
  if (isVirtual) return (from: startsAt, to: endsAt);
  final from = (categoryStartsAt ?? startsAt).subtract(
    const Duration(hours: 2),
  );
  return (from: from, to: endsAt.add(const Duration(hours: 12)));
}

/// Whether [a] can be offered at all in the list: a running activity
/// recorded in FitFlex that has a route.
bool isListableRun(Activity a) =>
    (a.type == ActivityType.running || a.type == ActivityType.jogging) &&
    a.source == ActivitySource.fitflex &&
    a.hasRoute;

/// Labels [a] for an event whose category is [categoryMeters] long.
RunFit fitOf(
  Activity a, {
  required bool isVirtual,
  required DateTime? startsAt,
  required DateTime? endsAt,
  required int categoryMeters,
  required int toleranceBps,
  required Set<String> linkedActivityIds,
  DateTime? categoryStartsAt,
}) {
  if (!isListableRun(a)) return RunFit.notRecordedInApp;
  if (linkedActivityIds.contains(a.id)) return RunFit.linked;
  if (startsAt != null && endsAt != null) {
    final w = runWindow(
      isVirtual: isVirtual,
      startsAt: startsAt,
      endsAt: endsAt,
      categoryStartsAt: categoryStartsAt,
    );
    final at = a.startedAt.toUtc();
    if (at.isBefore(w.from) || at.isAfter(w.to)) return RunFit.outside;
  }
  // Only a virtual result needs the full distance (in-person runs are
  // evidence and any length may be added).
  if (isVirtual && categoryMeters > 0 && a.distanceKm != null) {
    final required = categoryMeters * (10000 - toleranceBps) / 10000;
    if (a.distanceKm! * 1000 < required) return RunFit.short;
  }
  return RunFit.available;
}
