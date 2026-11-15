// Security activity: the list of check-ins made from a web browser with the
// signed-in account (fitflex-functions docs/web-checkin-alerts-api.md), and,
// while the server allows it (`reportEnabled`), the "This wasn't me" report
// (docs/security-incident-report-api.md).
// Nothing here is kept on the device, and payloads are never logged.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../pin_flows.dart' show ForgotPinScreen, changePinAndReport;
import 'security_report_sheet.dart';

/// The member's report of an event. Only its progress is known here, never
/// what staff decided.
class SecurityReport {
  const SecurityReport({
    required this.incidentId,
    required this.status,
    this.protectionPending = false,
    this.protectionRetryable = true,
    this.protectionKnown = false,
  });

  final String incidentId;

  /// `open`, `acknowledged` or `resolved`.
  final String status;

  /// The member asked to secure the account and that is not in place yet.
  /// A repeat report retries it. False when the server does not say (an
  /// older backend).
  final bool protectionPending;

  /// False only when the server says so: no retry will help (the member
  /// should contact support). [protectionPending] is still true then.
  final bool protectionRetryable;

  /// The server sent `protectionPending` at all. An older backend does not,
  /// and then the list says nothing either way about the protection.
  final bool protectionKnown;

  /// Securing is still owed. A resolved report is never pending.
  bool get securingPending => protectionPending && status != 'resolved';

  /// The i18n key of the report chip. An unknown status reads as reported.
  String get statusKey => switch (status) {
    'acknowledged' => 'secAct.report.status.acknowledged',
    'resolved' => 'secAct.report.status.resolved',
    _ => 'secAct.report.status.open',
  };

  static SecurityReport? fromJson(Object? j) => j is Map
      ? SecurityReport(
          incidentId: j['incidentId']?.toString() ?? '',
          status: j['status']?.toString() ?? 'open',
          protectionPending: j['protectionPending'] == true,
          protectionRetryable: j['protectionRetryable'] != false,
          protectionKnown: j['protectionPending'] is bool,
        )
      : null;
}

/// One event of the list. Unknown kinds are kept and shown generically.
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.gymName,
    required this.status,
    this.report,
  });

  final String id;
  final String kind;
  final DateTime? occurredAt;
  final String? gymName;
  final String status;

  /// Null until the member reports the event.
  final SecurityReport? report;

  SecurityEvent withReport(SecurityReport r) => SecurityEvent(
    id: id,
    kind: kind,
    occurredAt: occurredAt,
    gymName: gymName,
    status: status,
    report: r,
  );

  bool get isWebCheckin => kind == 'web_checkin';

  /// The i18n key of the status chip, or null for a status we don't know.
  /// `notified` is the legacy name of `inbox`.
  String? get statusKey => securityStatusKey(status);

  factory SecurityEvent.fromJson(Map<String, dynamic> j) {
    final gym = j['gym'];
    final name = gym is Map ? gym['name']?.toString().trim() : null;
    return SecurityEvent(
      id: j['id']?.toString() ?? '',
      kind: j['kind']?.toString() ?? '',
      occurredAt: DateTime.tryParse(j['occurredAt']?.toString() ?? '')?.toUtc(),
      gymName: name == null || name.isEmpty ? null : name,
      status: j['status']?.toString() ?? '',
      report: SecurityReport.fromJson(j['report']),
    );
  }
}

String? securityStatusKey(String status) => switch (status) {
  'inbox' || 'notified' => 'secAct.status.inbox',
  'recorded' => 'secAct.status.recorded',
  _ => null,
};

/// "9 Nov 2026, 14:30 EAT": the time in Africa/Dar_es_Salaam (UTC+3, no
/// daylight saving), whatever the phone's own zone.
String securityEventTime(DateTime? at, {String locale = 'en'}) {
  if (at == null) return '-';
  final u = at.toUtc().add(const Duration(hours: 3));
  final eat = DateTime(u.year, u.month, u.day, u.hour, u.minute);
  return '${formatDate(eat, locale: locale)}, '
      '${formatTimeOfDay(eat, locale: locale)} EAT';
}

class SecurityActivityPage extends StatefulWidget {
  const SecurityActivityPage({super.key});

  @override
  State<SecurityActivityPage> createState() => _SecurityActivityPageState();
}

class _SecurityActivityPageState extends State<SecurityActivityPage> {
  static const _pageSize = 20;

  final _events = <SecurityEvent>[];
  String? _next;
  bool _started = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _off = false;
  bool _failed = false;
  bool _moreFailed = false;

  /// The server's `reportEnabled`: false (or absent) hides every report
  /// action, and the screen is the read-only list.
  bool _reportEnabled = false;

  /// The event whose report is being sent. One at a time.
  String? _reporting;

  /// What to say under an event after a report (an error, or "limited"),
  /// until the page is left.
  final _notices = <String, _ReportNotice>{};

  /// Events whose protection a report call of this visit said had failed,
  /// with what that call knew (the PIN step, whether a retry can help).
  /// The list says the same through `report.protectionPending`, which also
  /// survives leaving the page; see [_protectionNotice].
  final _protection = <String, _FailedProtection>{};

  /// Events whose retry is paused. The server ignores a repeat within 60
  /// seconds of the last attempt and answers it like a failure, so the
  /// retry is not offered meanwhile. In memory only.
  final _cooldowns = <String, Timer>{};

  /// The server's cooldown between attempts.
  static const _retryCooldown = Duration(seconds: 60);

  @override
  void dispose() {
    _clearCooldowns();
    super.dispose();
  }

  void _clearCooldowns() {
    for (final t in _cooldowns.values) {
      t.cancel();
    }
    _cooldowns.clear();
  }

  void _startCooldown(String eventId) {
    _cooldowns.remove(eventId)?.cancel();
    _cooldowns[eventId] = Timer(_retryCooldown, () {
      _cooldowns.remove(eventId);
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  static List<SecurityEvent> _parse(Map<String, dynamic> body) => [
    for (final e in (body['events'] as List?) ?? const [])
      if (e is Map) SecurityEvent.fromJson(e.cast<String, dynamic>()),
  ];

  static String? _cursor(Map<String, dynamic> body) {
    final n = body['next']?.toString();
    return n == null || n.isEmpty ? null : n;
  }

  /// Reads the first page. True when the list was read. A refresh that
  /// fails keeps the list that is showing.
  Future<bool> _load({bool refresh = false}) async {
    final api = AppScope.of(context).api;
    if (!refresh) {
      setState(() {
        _loading = true;
        _failed = false;
        _off = false;
      });
    }
    try {
      final body = await api.securityActivity(limit: _pageSize);
      if (!mounted) return false;
      setState(() {
        _events
          ..clear()
          ..addAll(_parse(body));
        _next = _cursor(body);
        _reportEnabled = body['reportEnabled'] == true;
        _off = false;
        _failed = false;
        _moreFailed = false;
        _loading = false;
      });
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        _off = e.status == 404;
        _failed = !_off && (!refresh || _events.isEmpty);
        _loading = false;
        if (_off) {
          _events.clear();
          _reportEnabled = false;
          _notices.clear();
          _protection.clear();
          _clearCooldowns();
        }
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _failed = _events.isEmpty;
        _loading = false;
      });
      return false;
    }
  }

  Future<void> _more() async {
    final cursor = _next;
    if (cursor == null || _loadingMore) return;
    final api = AppScope.of(context).api;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final body = await api.securityActivity(limit: _pageSize, before: cursor);
      if (!mounted) return;
      setState(() {
        _events.addAll(_parse(body));
        _next = _cursor(body);
        _reportEnabled = body['reportEnabled'] == true;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  Future<void> _askReport(SecurityEvent event) async {
    if (_reporting != null) return;
    final secure = await showSecurityReportSheet(context);
    if (secure == null || !mounted) return;
    await _report(event, secure);
  }

  /// Sends the report. Also the retry: the server answers a repeat with the
  /// same incident, and applies a protection that failed the first time.
  Future<void> _report(SecurityEvent event, bool secure) async {
    // One at a time: a second tap while a request is in flight does nothing.
    if (_reporting != null) return;
    // Already reported: this is a repeat, and the list may have moved on.
    final repeat = event.report != null;
    final scope = AppScope.of(context);
    final snack = FFSnack.of(context);
    final done = context.tr('secAct.report.done');
    final unavailable = context.tr('secAct.report.err.unavailable');
    setState(() {
      _reporting = event.id;
      _notices.remove(event.id);
    });
    final SecurityReportResult result;
    try {
      result = SecurityReportResult.fromJson(
        await scope.api.reportSecurityActivity(event.id, secureAccount: secure),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // 401: the session is over and ApiClient has already signed out.
      if (e.status == 401) return setState(() => _reporting = null);
      if (e.status == 404) {
        // Switched off, or no longer this member's event.
        setState(() => _reporting = null);
        snack.error(unavailable);
        await _load(refresh: true);
        return;
      }
      // 429 report_limit_reached: the cap is a rolling day and the server's
      // retryAfterSeconds is the real wait until a slot frees (1..86400).
      if (e.status == 429) {
        setState(() {
          _reporting = null;
          _notices[event.id] = _ReportNotice(
            securityReportLimitMessage(context.tr, e.body),
          );
        });
        return;
      }
      // A 4xx was refused outright. Anything else may have been taken up.
      final reached = e.status < 400 || e.status >= 500;
      return _attemptError(
        event,
        secure: secure,
        repeat: repeat,
        claimed: reached && (secure || repeat),
        messageKey: 'secAct.report.err.failed',
      );
    } catch (_) {
      if (!mounted) return;
      // No answer (offline, timeout): the request may still have arrived.
      return _attemptError(
        event,
        secure: secure,
        repeat: repeat,
        claimed: secure || repeat,
        messageKey: 'secAct.report.err.network',
      );
    }
    if (!mounted) {
      // The page was left meanwhile; a session the server ended still has
      // to end here.
      if (result.signedOut) await scope.auth.signOut();
      return;
    }
    final reported = SecurityReport(
      incidentId: result.incidentId,
      status: result.status,
      protectionPending: result.failed,
      protectionRetryable: result.retryable,
      protectionKnown: true,
    );
    if (result.failed && !result.signedOut) {
      // Not secured, says this call. That is a real failed attempt, or the
      // server's answer to a repeat it ignored (inside its 60 seconds, or
      // while an earlier attempt, perhaps one whose answer was lost, is
      // still running). So the list is read first and has the last word:
      // the notice shows only if the list agrees, or cannot say.
      // What the member can still do about the PIN, if anything:
      // - the PIN is already off (Change PIN would answer
      //   pin_reset_required): Forgot PIN;
      // - FitFlex holds a PIN that still works: Change PIN;
      // - no PIN held by FitFlex, or PINs off: only the retry.
      final pin = result.pinResetRequired
          ? (scope.auth.pinResetEnabled ? _PinRoute.forgot : null)
          : (!result.pinNotApplicable && scope.auth.pinLoginEnabled
                ? _PinRoute.change
                : null);
      await _load(refresh: true);
      if (!mounted) return;
      setState(() {
        _reporting = null;
        final at = _events.indexWhere((e) => e.id == event.id);
        // The list was not read, or does not show the report yet.
        if (at >= 0 && _events[at].report == null) {
          _events[at] = _events[at].withReport(reported);
        }
        _protection[event.id] = _FailedProtection(
          pin: pin,
          retryable: result.retryable,
        );
        // Either way the server does nothing on a repeat for 60 seconds
        // and would answer it with this same failure, so the retry waits.
        if (result.retryable) _startCooldown(event.id);
      });
      return;
    }
    setState(() {
      _reporting = null;
      final at = _events.indexWhere((e) => e.id == event.id);
      if (at >= 0) _events[at] = _events[at].withReport(reported);
      _protection.remove(event.id);
      _cooldowns.remove(event.id)?.cancel();
      if (result.limited && !result.signedOut) {
        _notices[event.id] = _ReportNotice(
          context.tr('secAct.report.limited'),
          tone: FFAlertTone.info,
        );
      }
    });
    if (result.signedOut) {
      await showSecurityReportSignedOutDialog(
        context,
        pinResetRequired: result.pinResetRequired,
      );
      // The app's own sign-out: clears the session and the router shows
      // sign-in.
      return scope.auth.signOut();
    }
    if (!result.limited) snack.success(done);
    await _load(refresh: true);
  }

  /// A report call that got no usable answer. [claimed]: it asked to secure
  /// (or was a repeat) and may have reached the server, which then counts
  /// it as an attempt: the retry waits out the 60 seconds like any other,
  /// and the list is read again, because the report may exist and the
  /// account may even be secured.
  Future<void> _attemptError(
    SecurityEvent event, {
    required bool secure,
    required bool repeat,
    required bool claimed,
    required String messageKey,
  }) async {
    setState(() {
      _reporting = null;
      _notices[event.id] = _ReportNotice(
        // A repeat is the retry of securing; the report itself was sent.
        context.tr(repeat ? 'secAct.report.err.retryFailed' : messageKey),
        retry: secure,
      );
      if (claimed) _startCooldown(event.id);
    });
    if (!claimed && !repeat) return;
    final read = await _load(refresh: true);
    if (!mounted || !read) return;
    final at = _events.indexWhere((e) => e.id == event.id);
    final report = at < 0 ? null : _events[at].report;
    // The list cannot say (no report, or an older backend): the error stays.
    if (report == null || !report.protectionKnown) return;
    // Nothing is owed any more, or a first report did arrive after all:
    // the list's own state is shown instead of the error. A failed retry
    // of securing that is still owed keeps its error.
    if (!report.securingPending || !repeat) {
      setState(() => _notices.remove(event.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('secAct.title'))),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: FFSpinner());
    final Widget content;
    if (_off) {
      content = FFEmptyState(
        icon: Icons.shield_outlined,
        title: context.tr('secAct.off.title'),
        body: context.tr('secAct.off.body'),
      );
    } else if (_failed) {
      content = FFErrorState(
        title: context.tr('secAct.loadFailed'),
        retryLabel: context.tr('comms.retry'),
        onRetry: _load,
      );
    } else if (_events.isEmpty) {
      content = FFEmptyState(
        icon: Icons.shield_outlined,
        title: context.tr('secAct.empty.title'),
        body: context.tr('secAct.empty.body'),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _events)
            SecurityActivityRow(
              event: e,
              onReport: _reportEnabled && e.isWebCheckin && e.report == null
                  ? () => _askReport(e)
                  : null,
              reporting: _reporting == e.id,
              busy: _reporting != null,
              notice: _noticeFor(e),
            ),
          if (_moreFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Text(
                context.tr('secAct.loadFailed'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_next != null)
            _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(FFTokens.spacingMd),
                    child: Center(child: FFSpinner()),
                  )
                : FFButton(
                    key: const Key('security-activity-more'),
                    label: context.tr(
                      _moreFailed ? 'comms.retry' : 'secAct.loadMore',
                    ),
                    variant: FFButtonVariant.secondary,
                    onPressed: _more,
                  ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        key: const Key('security-activity-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (!_off)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: Text(
                context.tr('secAct.intro'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          content,
        ],
      ),
    );
  }

  /// The "could not secure" notice of an event, from the list
  /// (`report.protectionPending`, which survives leaving the page) and from
  /// what a report call of this visit said. Null when securing is not owed.
  _ReportNotice? _protectionNotice(SecurityEvent event) {
    final report = event.report;
    final local = _protection[event.id];
    final listed = report != null && report.securingPending;
    if (!listed) {
      // Nothing from this visit either, or the list now says positively
      // that nothing is owed (secured elsewhere, or resolved by staff).
      if (local == null) return null;
      if (report != null &&
          (report.protectionKnown || report.status == 'resolved')) {
        return null;
      }
    }
    final retryable =
        (local?.retryable ?? true) && (report?.protectionRetryable ?? true);
    final pin = local?.pin;
    return _ReportNotice(
      context.tr(switch (pin) {
        _PinRoute.forgot => 'secAct.report.failedForgotPin',
        _PinRoute.change => 'secAct.report.failedChangePin',
        null =>
          retryable ? 'secAct.report.failed' : 'secAct.report.failedSupport',
      }),
      tone: FFAlertTone.warning,
      retry: retryable ? true : null,
      retryKey: 'secAct.report.failedRetry',
      pin: pin,
      // With a PIN message above, the pointer to support is its own line.
      support: !retryable && pin != null,
    );
  }

  /// The message under an event: the outcome or error of a report, or that
  /// the account is still not secured, with the retry and (when known) the
  /// way to change the PIN. One notice per event: an error of this visit
  /// comes before the list's state.
  Widget? _noticeFor(SecurityEvent event) {
    if (!_reportEnabled) return null;
    final n = _notices[event.id] ?? _protectionNotice(event);
    if (n == null) return null;
    final retry = n.retry;
    final busy = _reporting != null;
    // Set only by an attempt to secure; it holds every retry of the event.
    final cooling = _cooldowns.containsKey(event.id);
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      key: Key('security-report-notice-${event.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: FFAlert(message: n.message, tone: n.tone),
        ),
        if (n.support) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('secAct.report.support'),
            key: Key('security-report-support-${event.id}'),
            style: small,
          ),
        ],
        if (n.pin == _PinRoute.change) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: Key('security-report-change-pin-${event.id}'),
            label: context.tr('member.changePin'),
            icon: Icons.lock_outline,
            maxLines: 3,
            fullWidth: true,
            onPressed: busy ? null : () => changePinAndReport(context),
          ),
        ],
        if (n.pin == _PinRoute.forgot) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: Key('security-report-forgot-pin-${event.id}'),
            label: context.tr('pin.forgotTitle'),
            icon: Icons.lock_reset,
            maxLines: 3,
            fullWidth: true,
            onPressed: busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ForgotPinScreen(),
                    ),
                  ),
          ),
        ],
        if (retry != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: Key('security-report-retry-${event.id}'),
            label: context.tr(n.retryKey),
            maxLines: 3,
            fullWidth: true,
            variant: FFButtonVariant.secondary,
            loading: _reporting == event.id,
            onPressed: busy || cooling ? null : () => _report(event, retry),
          ),
          if (cooling) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Semantics(
              liveRegion: true,
              child: Text(
                context.tr('secAct.report.retryWait'),
                key: Key('security-report-wait-${event.id}'),
                style: small,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// The 429 `report_limit_reached` message, with the server's real wait
/// (`retryAfterSeconds`, 1..86400) when it gave one: minutes up to an hour,
/// else hours, always rounded up so the member is never told to come back
/// early. Without a usable wait: "try again later".
String securityReportLimitMessage(String Function(String) tr, Object? body) {
  final raw = body is Map ? body['retryAfterSeconds'] : null;
  final seconds = raw is num && raw.isFinite ? raw.ceil() : null;
  if (seconds == null || seconds < 1 || seconds > 86400) {
    return tr('secAct.report.err.limit');
  }
  final minutes = (seconds / 60).ceil();
  if (minutes == 1) return tr('secAct.report.err.limitMinute');
  if (minutes < 60) {
    return tr('secAct.report.err.limitMinutes').replaceAll('{n}', '$minutes');
  }
  final hours = (seconds / 3600).ceil();
  if (hours == 1) return tr('secAct.report.err.limitHour');
  return tr('secAct.report.err.limitHours').replaceAll('{n}', '$hours');
}

/// What a report call said when it could not secure the account.
class _FailedProtection {
  const _FailedProtection({required this.pin, required this.retryable});

  /// Where to send the member about the PIN, or null for nowhere.
  final _PinRoute? pin;

  /// False: the server said no retry will help.
  final bool retryable;
}

class _ReportNotice {
  const _ReportNotice(
    this.message, {
    this.tone = FFAlertTone.error,
    this.retry,
    this.retryKey = 'comms.retry',
    this.pin,
    this.support = false,
  });

  final String message;
  final FFAlertTone tone;

  /// The choice to send again (`secureAccount`), or null for no retry.
  final bool? retry;
  final String retryKey;

  /// Where to send the member about the PIN, or null for nowhere.
  final _PinRoute? pin;

  /// Adds the line that points to FitFlex support.
  final bool support;
}

/// The PIN step offered when the account could not be secured.
enum _PinRoute { change, forgot }

/// One event: icon, what happened, where, when (EAT), a status chip, the
/// report chip once reported, and the "This wasn't me" action while
/// [onReport] is set.
class SecurityActivityRow extends StatelessWidget {
  const SecurityActivityRow({
    super.key,
    required this.event,
    this.onReport,
    this.reporting = false,
    this.busy = false,
    this.notice,
  });

  final SecurityEvent event;

  /// Opens the report sheet. Null: no action (reporting off, already
  /// reported, or not a web check-in).
  final VoidCallback? onReport;

  /// This event's report is being sent.
  final bool reporting;

  /// Some report is being sent: the action does nothing meanwhile.
  final bool busy;

  /// Shown under the event (the outcome of a report, or its error).
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final title = context.tr(
      event.isWebCheckin ? 'secAct.row.title' : 'secAct.kind.other',
    );
    final gym = event.gymName ?? context.tr('secAct.row.gymUnknown');
    final time = securityEventTime(event.occurredAt, locale: lang);
    final statusKey = event.statusKey;
    final status = statusKey == null ? null : context.tr(statusKey);
    final report = event.report;
    final reported = report == null ? null : context.tr(report.statusKey);
    final details = Semantics(
      container: true,
      label: [title, gym, time, ?status, ?reported].join(', '),
      excludeSemantics: true,
      child: _details(context, title, gym, time, status, reported),
    );
    final onReport = this.onReport;
    if (onReport == null && notice == null) return FFCard(child: details);
    final action = context.tr('secAct.report.action');
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          details,
          if (notice != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            notice!,
          ],
          if (onReport != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FFButton(
              key: Key('security-report-${event.id}'),
              label: action,
              semanticLabel:
                  '$action. ${context.tr('secAct.report.actionHint')}',
              icon: Icons.flag_outlined,
              maxLines: 3,
              fullWidth: true,
              variant: FFButtonVariant.secondary,
              loading: reporting,
              onPressed: busy && !reporting ? null : onReport,
            ),
          ],
        ],
      ),
    );
  }

  Widget _details(
    BuildContext context,
    String title,
    String gym,
    String time,
    String? status,
    String? reported,
  ) {
    final theme = Theme.of(context);
    final statusKey = event.statusKey;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.isWebCheckin ? Icons.language : Icons.shield_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: FFTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: FFTokens.spacingXs),
                Text(gym, style: theme.textTheme.bodyMedium),
                Text(time, style: theme.textTheme.bodySmall),
                if (status != null) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  FFBadge(
                    label: status,
                    tone: statusKey == 'secAct.status.inbox'
                        ? FFBadgeTone.info
                        : FFBadgeTone.gray,
                    wrap: true,
                  ),
                ],
                if (reported != null) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  FFBadge(
                    key: Key('security-report-status-${event.id}'),
                    label: reported,
                    tone: event.report?.status == 'resolved'
                        ? FFBadgeTone.gray
                        : FFBadgeTone.warning,
                    wrap: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
