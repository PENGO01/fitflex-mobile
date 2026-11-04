// Vendor smart import V3: the apply loop as a state machine against a fake
// server: chunks until nothing remains, the waits for a busy server, the
// give-up into a calm pause, a finished batch found after a refusal, a retry
// that must not trust a stale `partial`, and a page that is left mid-run.
import 'package:fitflexmobile/screens/vendor/import/import_apply.dart';
import 'package:fitflexmobile/screens/vendor/import/import_models.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_support.dart';

ImportBatch batch(
  String status, {
  int applied = 0,
  int failed = 0,
  bool include = false,
}) => ImportBatch.from(
  batchJson(
    'vib_1',
    status: status,
    include: include,
    counts_: counts(applied: applied, failed: failed),
  ),
)!;

ApplyResponse res(ImportBatch b, {int processed = 5, int remaining = 0}) =>
    ApplyResponse(batch: b, processed: processed, remaining: remaining);

ApiException refused(int status, String code, [Map<String, dynamic>? extra]) =>
    ApiException(status, {'error': code, ...?extra});

/// Answers each call from a script: an [ApplyResponse] or an exception.
class Fake implements ImportGateway {
  Fake({
    this.applies = const [],
    this.retries = const [],
    this.details = const [],
  });
  final List<Object> applies;
  final List<Object> retries;
  final List<Object?> details;
  final calls = <String>[];
  final includes = <bool>[];
  var _a = 0, _r = 0, _d = 0;

  Future<ApplyResponse> _next(List<Object> script, int i) async {
    final v = script[i < script.length ? i : script.length - 1];
    if (v is ApplyResponse) return v;
    throw v;
  }

  @override
  Future<ApplyResponse> apply(String id, {required bool includeNeedsReview}) {
    calls.add('apply');
    includes.add(includeNeedsReview);
    return _next(applies, _a++);
  }

  @override
  Future<ApplyResponse> retry(String id) {
    calls.add('retry');
    return _next(retries, _r++);
  }

  @override
  Future<ImportDetail?> detail(String id) async {
    calls.add('detail');
    final v = details.isEmpty
        ? null
        : details[_d < details.length ? _d : details.length - 1];
    _d++;
    if (v is Exception) throw v;
    return v == null ? null : ImportDetail(batch: v as ImportBatch);
  }
}

void main() {
  final slept = <Duration>[];
  Future<void> sleep(Duration d) async => slept.add(d);
  setUp(slept.clear);

  Future<ApplyOutcome> drive(
    Fake g, {
    ApplyStart first = ApplyStart.apply,
    bool include = false,
    int maxWaits = 5,
    bool Function()? stop,
    List<(ImportBatch, int)>? progress,
  }) => driveApply(
    gateway: g,
    id: 'vib_1',
    includeNeedsReview: include,
    first: first,
    maxWaits: maxWaits,
    sleep: sleep,
    shouldStop: stop,
    onProgress: progress == null ? null : (b, r) => progress.add((b, r)),
  );

  test('repeats until nothing remains, reporting each answer', () async {
    final seen = <(ImportBatch, int)>[];
    final g = Fake(
      applies: [
        res(batch('applying', applied: 4), remaining: 6),
        res(batch('applying', applied: 8), remaining: 2),
        res(batch('applied', applied: 10), remaining: 0),
      ],
    );
    final out = await drive(g, progress: seen);
    expect(out, isA<ApplyDone>());
    expect((out as ApplyDone).batch.status, BatchStatus.applied);
    expect(g.calls, ['apply', 'apply', 'apply']);
    expect(seen.map((e) => e.$2), [6, 2, 0]);
    expect(slept, isEmpty);
  });

  test('sends the first choice on every call', () async {
    final g = Fake(
      applies: [
        res(batch('applying', applied: 4), remaining: 6),
        res(batch('applied', applied: 10)),
      ],
    );
    await drive(g, include: true);
    expect(g.includes, [true, true]);
  });

  test('partial is a finished state too', () async {
    final g = Fake(applies: [res(batch('partial', applied: 8, failed: 2))]);
    final out = await drive(g);
    expect((out as ApplyDone).batch.status, BatchStatus.partial);
  });

  test(
    'apply_in_progress: waits, then finds the batch already finished',
    () async {
      final g = Fake(
        applies: [refused(409, 'apply_in_progress')],
        details: [batch('applied', applied: 10)],
      );
      final out = await drive(g);
      expect((out as ApplyDone).batch.status, BatchStatus.applied);
      expect(g.calls, ['apply', 'detail']);
      expect(slept, isEmpty);
    },
  );

  test('409 then finished: wait, call again, done', () async {
    final g = Fake(
      applies: [
        refused(409, 'apply_in_progress'),
        res(batch('applied', applied: 10)),
      ],
      details: [batch('applying', applied: 3)],
    );
    final out = await drive(g);
    expect(out, isA<ApplyDone>());
    expect(g.calls, ['apply', 'detail', 'apply']);
    expect(slept, hasLength(1));
    expect(slept.single, const Duration(milliseconds: 1500));
  });

  test('import_busy waits as long as the server asked', () async {
    final g = Fake(
      applies: [
        refused(503, 'import_busy', {'retryAfterSeconds': 5}),
        refused(503, 'import_busy', {'retryAfterSeconds': 120}),
        res(batch('applied', applied: 10)),
      ],
    );
    await drive(g);
    expect(slept, [const Duration(seconds: 5), const Duration(seconds: 30)]);
  });

  test(
    'rate_limited honours retryAfterSeconds and backs off without it',
    () async {
      final g = Fake(
        applies: [
          refused(429, 'rate_limited', {'retryAfterSeconds': 7}),
          refused(429, 'rate_limited'),
          refused(429, 'rate_limited'),
          res(batch('applied', applied: 10)),
        ],
      );
      await drive(g);
      expect(slept, [
        const Duration(seconds: 7),
        const Duration(milliseconds: 3000),
        const Duration(milliseconds: 6000),
      ]);
    },
  );

  test('a dropped connection is waited out like a busy server', () async {
    final g = Fake(
      applies: [StateError('socket'), res(batch('applied', applied: 10))],
    );
    final out = await drive(g);
    expect(out, isA<ApplyDone>());
    expect(slept, hasLength(1));
  });

  test('gives up after maxWaits in a calm pause with the reason', () async {
    final g = Fake(applies: [refused(503, 'import_busy')]);
    final out = await drive(g, maxWaits: 2);
    expect(out, isA<ApplyPaused>());
    expect((out as ApplyPaused).reason, ImportPause.busy);
    expect(g.calls.where((c) => c == 'apply'), hasLength(3));
    expect(slept, hasLength(2));

    final net = await drive(Fake(applies: [StateError('x')]), maxWaits: 1);
    expect((net as ApplyPaused).reason, ImportPause.network);
    final rate = await drive(
      Fake(applies: [refused(429, 'rate_limited')]),
      maxWaits: 1,
    );
    expect((rate as ApplyPaused).reason, ImportPause.rate);
  });

  test('a pause remembers the last batch it saw', () async {
    final g = Fake(
      applies: [
        res(batch('applying', applied: 4), remaining: 6),
        refused(503, 'import_busy'),
      ],
    );
    final out = await drive(g, maxWaits: 1) as ApplyPaused;
    expect(out.batch!.counts!.applied, 4);
  });

  test('the wait counter starts again after a good answer', () async {
    final g = Fake(
      applies: [
        refused(503, 'import_busy'),
        res(batch('applying', applied: 4), remaining: 6),
        refused(503, 'import_busy'),
        res(batch('applied', applied: 10)),
      ],
    );
    final out = await drive(g, maxWaits: 1);
    expect(out, isA<ApplyDone>());
  });

  test('another refusal ends as failed, with the error', () async {
    final g = Fake(applies: [refused(403, 'profile_import_owner_only')]);
    final out = await drive(g);
    expect(out, isA<ApplyFailed>());
    expect((out as ApplyFailed).error, isA<ApiException>());
    expect(slept, isEmpty);
  });

  test('request_aborted (499) is a refusal, not a wait', () async {
    final out = await drive(Fake(applies: [refused(499, 'request_aborted')]));
    expect(out, isA<ApplyFailed>());
  });

  test('batch_expired on retry ends as failed', () async {
    final g = Fake(retries: [refused(409, 'batch_expired')]);
    final out = await drive(g, first: ApplyStart.retry);
    expect(out, isA<ApplyFailed>());
    expect(g.calls, ['retry']);
  });

  test('not_ready: the batch had finished meanwhile', () async {
    final g = Fake(
      applies: [
        refused(409, 'not_ready', {'batchStatus': 'applied'}),
      ],
      details: [batch('applied', applied: 10)],
    );
    final out = await drive(g);
    expect(out, isA<ApplyDone>());
  });

  test('not_ready on a retry does not trust a stale partial', () async {
    final g = Fake(
      retries: [refused(409, 'not_ready')],
      details: [batch('partial', applied: 8, failed: 2)],
    );
    final out = await drive(g, first: ApplyStart.retry);
    expect(out, isA<ApplyFailed>());
  });

  test('retry first, then apply for the rest', () async {
    final g = Fake(
      retries: [res(batch('applying', applied: 9, failed: 1), remaining: 1)],
      applies: [res(batch('applied', applied: 10))],
    );
    final out = await drive(g, first: ApplyStart.retry);
    expect(out, isA<ApplyDone>());
    expect(g.calls, ['retry', 'apply']);
  });

  test(
    'remaining 0 with the status not moved: reads the batch once more',
    () async {
      final g = Fake(
        applies: [res(batch('applying', applied: 10), remaining: 0)],
        details: [batch('applied', applied: 10)],
      );
      final out = await drive(g);
      expect((out as ApplyDone).batch.status, BatchStatus.applied);
      expect(g.calls, ['apply', 'detail']);
    },
  );

  test('remaining 0 and the re-read fails: done with what we have', () async {
    final g = Fake(
      applies: [res(batch('applying', applied: 10), remaining: 0)],
      details: [StateError('offline')],
    );
    final out = await drive(g);
    expect(out, isA<ApplyDone>());
  });

  test('leaving the page stops the loop between calls', () async {
    var left = false;
    final g = Fake(applies: [res(batch('applying', applied: 4), remaining: 6)]);
    final out = await driveApply(
      gateway: g,
      id: 'vib_1',
      includeNeedsReview: false,
      sleep: sleep,
      shouldStop: () => left,
      onProgress: (_, _) => left = true,
    );
    expect(out, isA<ApplyPaused>());
    expect(g.calls, ['apply']);
  });

  test(
    'a server stuck on "0 done, some left" ends in a pause, not a loop',
    () async {
      final g = Fake(
        applies: [
          res(batch('applying', applied: 4), processed: 0, remaining: 6),
        ],
      );
      final out = await drive(g, maxWaits: 3);
      expect(out, isA<ApplyPaused>());
      expect(g.calls.length, lessThan(10));
    },
  );
}
