import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import 'activity.dart';
import 'gps_source.dart';
import 'phone_steps.dart' show StepStore;
import 'run_metrics.dart';

enum RunState { idle, recording, paused, finished }

// Why the server refuses a run, and the line that tells the member.
const _runRefusals = {
  'too_short': 'run.tooShort',
  'invalid_route': 'run.fail.weakGps',
  'too_fast': 'run.fail.tooFast',
  'too_long': 'run.fail.tooLong',
  'started_in_future': 'run.fail.clock',
  'too_old': 'run.fail.tooOld',
};

/// The message (an i18n key) for a run that couldn't be saved: the server's
/// own reason when it gave one, "no connection" when it was never reached,
/// and the general line otherwise.
String runSaveFailureKey(Object error) {
  if (error is ApiException) {
    return _runRefusals[error.code] ?? 'run.saveFailed';
  }
  // Timed out, or the phone couldn't reach the server at all.
  final kind = error.runtimeType.toString();
  if (error is TimeoutException ||
      kind.contains('SocketException') ||
      kind.contains('ClientException') ||
      kind.contains('HandshakeException')) {
    return 'run.fail.offline';
  }
  return 'run.saveFailed';
}

/// Records a run with GPS: start, pause/resume, finish, then save or
/// discard. Live numbers come from [trackMetrics]; the saved ones are
/// worked out by the server from the same track.
///
/// The run in progress is kept on the phone as it goes, so if the app is
/// closed or killed mid-run it comes back paused, ready to resume or finish.
/// The route is private to the member.
class RunRecorder extends ChangeNotifier {
  RunRecorder({
    required this.gps,
    required this.store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GpsSource gps;
  final StepStore store;
  final DateTime Function() _now;

  static const _key = 'run_in_progress_v1';

  RunState _state = RunState.idle;
  final List<List<TrackPoint>> _segments = [];
  RunMetrics _metrics = const RunMetrics();
  StreamSubscription<TrackPoint>? _sub;
  Timer? _ticker;
  DateTime? _segmentStart;
  Duration _banked = Duration.zero;
  GpsAccess? _access;
  bool _restored = false;
  int _unsaved = 0;

  // Events S6 (spec §10.2): the registration this run is recorded for and
  // the `clientRef` made when it began. Kept with the run on the phone so a
  // save that failed offline is retried with the same reference and the
  // server returns the first answer instead of adding the run twice.
  String? _eventRegistrationId;
  String? _clientRef;

  /// The registration this run is for, or null for a plain run.
  String? get eventRegistrationId => _eventRegistrationId;

  /// The reference sent with the event run (null for a plain run).
  String? get clientRef => _clientRef;

  /// Ties the run being recorded to an event registration. Call before
  /// [start]; the reference is made once and survives a restart of the app.
  /// Returns false (and changes nothing) when a run for another registration
  /// is already under way.
  bool bindEvent(String registrationId, {String Function()? makeRef}) {
    if (_eventRegistrationId == registrationId && _clientRef != null) {
      return true;
    }
    if (_state != RunState.idle || hasFix) return false;
    _eventRegistrationId = registrationId;
    _clientRef = (makeRef ?? _newClientRef)();
    return true;
  }

  /// Stops tying the run to an event (the run itself stays).
  Future<void> unbindEvent() async {
    _eventRegistrationId = null;
    _clientRef = null;
    if (_state != RunState.idle) await _persist();
  }

  static int _refSeq = 0;
  static String _newClientRef() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final n = (++_refSeq).toRadixString(36);
    return 'run-$t-$n-${identityHashCode(Object()).toRadixString(36)}';
  }

  bool get supported => gps.isSupported;
  RunState get state => _state;
  RunMetrics get metrics => _metrics;
  List<List<TrackPoint>> get segments => _segments;
  GpsAccess? get access => _access;

  /// Whether this run came back after the app was closed mid-run.
  bool get restored => _restored;

  /// Time recording, not counting pauses.
  Duration get elapsed =>
      _banked +
      (_state == RunState.recording && _segmentStart != null
          ? _now().difference(_segmentStart!)
          : Duration.zero);

  /// Whether a GPS fix has arrived yet.
  bool get hasFix => _segments.any((s) => s.isNotEmpty);

  TrackPoint? get lastPoint => _segments.lastOrNull?.lastOrNull;

  /// Picks up a run the app was recording when it closed.
  Future<void> restore() async {
    if (_state != RunState.idle) return;
    final raw = await store.read(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _segments
        ..clear()
        ..addAll([
          for (final seg in (json['segments'] as List? ?? const []))
            [for (final p in (seg as List)) ?TrackPoint.fromWire(p)],
        ]);
      _banked = Duration(seconds: (json['elapsed'] as num?)?.toInt() ?? 0);
      final reg = json['eventRegistrationId']?.toString() ?? '';
      final ref = json['clientRef']?.toString() ?? '';
      if (reg.isNotEmpty && ref.length >= 8) {
        _eventRegistrationId = reg;
        _clientRef = ref;
      }
      if (!hasFix) return;
      _metrics = trackMetrics(cleanTrack(_segments));
      _state = RunState.paused;
      _restored = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[RunRecorder] could not restore a run: $e');
    }
  }

  /// Starts (or resumes) recording. Returns false when location isn't
  /// available; [access] says why.
  Future<bool> start({
    required String notificationTitle,
    required String notificationText,
  }) async {
    if (!supported ||
        _state == RunState.recording ||
        _state == RunState.finished) {
      return false;
    }
    _access = await gps.ensureAccess();
    if (_access != GpsAccess.granted) {
      notifyListeners();
      return false;
    }
    _segments.add([]);
    _segmentStart = _now();
    _state = RunState.recording;
    _sub = gps
        .track(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
        )
        .listen(
          _onPoint,
          onError: (Object e) => debugPrint('[RunRecorder] GPS error: $e'),
        );
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
    notifyListeners();
    return true;
  }

  void _onPoint(TrackPoint p) {
    if (_state != RunState.recording || _segments.isEmpty) return;
    final seg = _segments.last;
    if (!acceptPoint(seg.lastOrNull, p)) return;
    seg.add(p);
    _metrics = trackMetrics(cleanTrack(_segments));
    if (++_unsaved >= 10) unawaited(_persist());
    notifyListeners();
  }

  Future<void> pause() async {
    if (_state != RunState.recording) return;
    await _stopGps();
    _state = RunState.paused;
    await _persist();
    notifyListeners();
  }

  Future<bool> resume({
    required String notificationTitle,
    required String notificationText,
  }) {
    _restored = false;
    return start(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  Future<void> finish() async {
    if (_state == RunState.idle || _state == RunState.finished) return;
    await _stopGps();
    _segments.removeWhere((s) => s.isEmpty);
    _metrics = trackMetrics(cleanTrack(_segments));
    _state = RunState.finished;
    await _persist();
    notifyListeners();
  }

  /// Saves the finished run. Returns the saved activity; throws on failure
  /// (the run stays so the member can try again).
  Future<Activity> save(
    ApiClient api, {
    String? notes,
    Map<String, dynamic>? shareWith,
    bool shareChosen = false,
  }) async {
    final body = {
      // Left out, the member's default audience applies.
      if (shareChosen) 'shareWith': shareWith,
      'type': 'running',
      'segments': [
        for (final seg in _segments) [for (final p in seg) p.toWire()],
      ],
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    final reg = _eventRegistrationId;
    final ref = _clientRef;
    final res = reg != null && ref != null
        ? await api.recordEventRun(reg, {...body, 'clientRef': ref})
        : await api.recordRun(body);
    final activity = Activity.fromJson(
      Map<String, dynamic>.from(res['activity'] as Map),
    );
    await discard();
    return activity;
  }

  /// Saves the run without adding it to the event (a refused link, or the
  /// member's choice): the plain run route, same run, no `clientRef`.
  Future<Activity> saveWithoutEvent(
    ApiClient api, {
    String? notes,
    Map<String, dynamic>? shareWith,
    bool shareChosen = false,
  }) async {
    _eventRegistrationId = null;
    _clientRef = null;
    return save(
      api,
      notes: notes,
      shareWith: shareWith,
      shareChosen: shareChosen,
    );
  }

  Future<void> discard() async {
    await _stopGps();
    _segments.clear();
    _metrics = const RunMetrics();
    _banked = Duration.zero;
    _state = RunState.idle;
    _restored = false;
    _eventRegistrationId = null;
    _clientRef = null;
    await store.write(_key, '');
    notifyListeners();
  }

  Future<void> _stopGps() async {
    if (_segmentStart != null) {
      _banked += _now().difference(_segmentStart!);
      _segmentStart = null;
    }
    _ticker?.cancel();
    _ticker = null;
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _persist() async {
    _unsaved = 0;
    await store.write(
      _key,
      jsonEncode({
        'segments': [
          for (final seg in _segments) [for (final p in seg) p.toWire()],
        ],
        'elapsed': elapsed.inSeconds,
        if (_eventRegistrationId != null && _clientRef != null) ...{
          'eventRegistrationId': _eventRegistrationId,
          'clientRef': _clientRef,
        },
      }),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
