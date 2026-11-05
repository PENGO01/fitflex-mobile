// Vendor smart import V3: the apply loop. One POST /apply works up to 200 rows
// and answers `{batch, processed, remaining}`; the client repeats it until the
// batch is applied or partial. Mirrors the portal's driveApply
// (src/lib/vendor-import.ts): a busy server (409 `apply_in_progress`, 503
// `import_busy`, 429 `rate_limited`) or a dropped connection is waited out
// with backoff (the server's `retryAfterSeconds` honoured) and then ends in a
// calm `paused` result the vendor can continue from. Any other refusal ends
// as `failed`. No UI and no network of its own: the gateway is injected.
import 'dart:async';

import '../../../shared/api_client.dart';
import 'import_errors.dart';
import 'import_models.dart';

/// `{batch, processed, remaining}` of an apply or retry call.
class ApplyResponse {
  const ApplyResponse({
    required this.batch,
    required this.processed,
    required this.remaining,
  });
  final ImportBatch batch;
  final int processed;
  final int remaining;
}

/// What the loop needs from the server. [ApiImportGateway] is the real one;
/// tests pass a fake.
abstract class ImportGateway {
  Future<ApplyResponse> apply(String id, {required bool includeNeedsReview});
  Future<ApplyResponse> retry(String id);
  Future<ImportDetail?> detail(String id);
}

class ApiImportGateway implements ImportGateway {
  const ApiImportGateway(this.api);
  final ApiClient api;

  ApplyResponse _response(Map<String, dynamic> json) {
    final batch = ImportBatch.from(json['batch']);
    if (batch == null) throw ApiException(502, null);
    final processed = json['processed'];
    final remaining = json['remaining'];
    return ApplyResponse(
      batch: batch,
      processed: processed is num ? processed.toInt() : 0,
      remaining: remaining is num ? remaining.toInt() : 0,
    );
  }

  @override
  Future<ApplyResponse> apply(
    String id, {
    required bool includeNeedsReview,
  }) async => _response(
    await api.vendorImportApply(id, includeNeedsReview: includeNeedsReview),
  );

  @override
  Future<ApplyResponse> retry(String id) async =>
      _response(await api.vendorImportRetry(id));

  @override
  Future<ImportDetail?> detail(String id) async =>
      ImportDetail.from(await api.vendorImport(id));
}

/// Why a run stopped to wait.
enum ImportPause { busy, rate, network }

sealed class ApplyOutcome {
  const ApplyOutcome();
}

/// The batch reached applied / partial / discarded.
class ApplyDone extends ApplyOutcome {
  const ApplyDone(this.batch);
  final ImportBatch batch;
}

/// Waited long enough; the vendor can continue. [batch] is the last one seen.
class ApplyPaused extends ApplyOutcome {
  const ApplyPaused(this.reason, this.batch, {this.retryAfterSeconds});
  final ImportPause reason;
  final ImportBatch? batch;

  /// What the server asked for when it limited the rate, if it said.
  final int? retryAfterSeconds;
}

/// Refused for good; [error] is what the server (or network) said.
class ApplyFailed extends ApplyOutcome {
  const ApplyFailed(this.error);
  final Object error;
}

/// Which call a run starts with.
enum ApplyStart { apply, retry }

/// After a refusal the batch may have finished meanwhile. For a retry, a
/// terminal `partial` read is NOT proof: it may be the state from before the
/// retry (failed rows still waiting), so it counts as finished only when
/// nothing failed.
bool _finishedFor(ApplyStart call, ImportBatch b) =>
    b.status.isTerminal &&
    (call == ApplyStart.apply || (b.counts?.failed ?? 0) == 0);

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// Repeats apply (or retry first) until the batch is finished. [onProgress]
/// gets each answer. [shouldStop] is asked between calls (the page was
/// left). [sleep], [maxWaits] and [baseDelay] are for tests and tuning.
Future<ApplyOutcome> driveApply({
  required ImportGateway gateway,
  required String id,
  required bool includeNeedsReview,
  ApplyStart first = ApplyStart.apply,
  void Function(ImportBatch batch, int remaining)? onProgress,
  bool Function()? shouldStop,
  Future<void> Function(Duration)? sleep,
  int maxWaits = 5,
  Duration baseDelay = const Duration(milliseconds: 1500),
}) async {
  final pause = sleep ?? _wait;
  var call = first;
  var waits = 0;
  var stalls = 0;
  ImportBatch? last;
  for (;;) {
    if (shouldStop?.call() ?? false) {
      return ApplyPaused(ImportPause.busy, last);
    }
    final attempted = call;
    try {
      final res = attempted == ApplyStart.retry
          ? await gateway.retry(id)
          : await gateway.apply(id, includeNeedsReview: includeNeedsReview);
      call = ApplyStart.apply;
      waits = 0;
      last = res.batch;
      onProgress?.call(res.batch, res.remaining);
      if (res.batch.status.isTerminal) return ApplyDone(res.batch);
      // A server that keeps answering "0 done, some left" would loop for
      // ever: after a few such answers stop and let the vendor continue.
      stalls = res.processed <= 0 && res.remaining > 0 ? stalls + 1 : 0;
      if (stalls >= maxWaits) return ApplyPaused(ImportPause.busy, last);
      if (stalls > 0) await pause(_backoff(baseDelay, stalls - 1));
      if (res.remaining <= 0) {
        // Nothing left but the status has not moved: read it once more.
        final fresh = await _detailOrNull(gateway, id);
        if (fresh != null && fresh.batch.status.isTerminal) {
          return ApplyDone(fresh.batch);
        }
        return ApplyDone(fresh?.batch ?? res.batch);
      }
    } catch (err) {
      final code = importErrorCode(err);
      final transient =
          (err is! ApiException && importErrorIsNetwork(err)) ||
          code == 'apply_in_progress' ||
          code == 'import_busy' ||
          code == 'rate_limited';
      if (!transient) {
        // An earlier request of ours may have finished the batch already.
        if (code == 'not_ready') {
          final fresh = await _detailOrNull(gateway, id);
          if (fresh != null && _finishedFor(attempted, fresh.batch)) {
            return ApplyDone(fresh.batch);
          }
        }
        return ApplyFailed(err);
      }
      final reason = err is! ApiException
          ? ImportPause.network
          : code == 'rate_limited'
          ? ImportPause.rate
          : ImportPause.busy;
      if (code == 'apply_in_progress') {
        // Our own earlier request may still be running, or has just finished.
        final fresh = await _detailOrNull(gateway, id);
        if (fresh != null) {
          last = fresh.batch;
          if (_finishedFor(attempted, fresh.batch)) {
            return ApplyDone(fresh.batch);
          }
        }
      }
      final after = importRetryAfterSeconds(err);
      if (waits >= maxWaits) {
        return ApplyPaused(
          reason,
          last,
          retryAfterSeconds: reason == ImportPause.rate ? after : null,
        );
      }
      final delay = after != null
          ? Duration(seconds: after > 30 ? 30 : after)
          : _backoff(baseDelay, waits);
      waits += 1;
      await pause(delay);
    }
  }
}

Duration _backoff(Duration base, int waits) {
  final ms = base.inMilliseconds * (1 << waits);
  return Duration(milliseconds: ms > 12000 ? 12000 : ms);
}

Future<ImportDetail?> _detailOrNull(ImportGateway g, String id) async {
  try {
    return await g.detail(id);
  } catch (_) {
    return null;
  }
}
