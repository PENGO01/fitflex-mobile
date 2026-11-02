import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_detail.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/event_summary.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/events/events_checkout.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/events/waitlist.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/shop_checkout.dart';
import '../../member_edit_profile_page.dart';
import '../../member_shell.dart';
import '../events_registration_gate.dart';
import '../register/participant_form.dart';
import '../register/self_profile.dart';

/// `/member/events/:eventId/register?mode=waitlist&ticketTypeId=<id>`
/// (events S7 spec §4.10): choose a sold-out ticket, check your own details,
/// accept the terms, join. There is no payment step: waiting is free and a
/// held ticket is paid for later through the normal order. One ticket, for
/// the member only (D70), so the "other people" modes are not offered.
class MemberEventWaitlistJoinPage extends StatefulWidget {
  const MemberEventWaitlistJoinPage({
    super.key,
    required this.eventId,
    this.ticketTypeId,
    this.options,
    this.selfProfile,
    this.now,
  });

  final String eventId;
  final String? ticketTypeId;
  final EventsOptions? options;
  final RegistrationSelfProfile? selfProfile;
  final DateTime? now;

  @override
  State<MemberEventWaitlistJoinPage> createState() =>
      _MemberEventWaitlistJoinPageState();
}

class _MemberEventWaitlistJoinPageState
    extends State<MemberEventWaitlistJoinPage> {
  EventDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _gone = false;
  bool _gated = false;

  String? _ticketId;
  EventParticipantInput? _me;
  ParticipantFields? _fields;
  ConsentText _consent = const ConsentText();
  bool _accepted = false;
  bool _joining = false;
  CheckoutAttempt? _attempt;
  String? _refusal;
  bool _showRegister = false;
  WaitlistEntry? _joined;
  final Map<String, FieldProblem> _serverProblems = {};

  final _heading = FocusNode(debugLabel: 'waitlist-join-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);
  RegistrationSelfProfile get _self =>
      widget.selfProfile ?? RegistrationSelfProfile.fromScope(context);
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) return;
    if (!eventsRegistrationAllowed(context, _options)) {
      _gated = true;
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _gone = false;
    });
    try {
      // The ticket's waitlist state must be fresh, so the saved copy is not
      // used here.
      final json = await _api.getEvent(widget.eventId);
      EventsCache.putDetail(widget.eventId, json);
      if (!mounted) return;
      final d = EventDetail.fromJson(json);
      setState(() {
        _detail = d;
        _loading = false;
      });
      EventsAnalytics.waitlistJoinStarted(eventId: d.id);
      final want = widget.ticketTypeId;
      if (want != null) {
        for (final t in _ticketTypes(d)) {
          if (t.id == want && t.canJoinWaitlist) _pick(t.id);
        }
      }
      _focusHeading();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e is ApiException && e.status == 404) {
          _gone = true;
        } else {
          _error = e;
        }
      });
    }
  }

  void _focusHeading() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _heading.requestFocus();
  });

  List<EventTicketType> _ticketTypes(EventDetail d) => [
    for (final c in d.categories) ...c.ticketTypes,
  ];

  EventCategory? _categoryOf(EventDetail d, String ticketId) {
    for (final c in d.categories) {
      for (final t in c.ticketTypes) {
        if (t.id == ticketId) return c;
      }
    }
    return null;
  }

  EventTicketType? _ticket(EventDetail d, String id) {
    for (final t in _ticketTypes(d)) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _pick(String ticketId) {
    final d = _detail;
    if (d == null) return;
    final cat = _categoryOf(d, ticketId);
    if (cat == null) return;
    final p = EventParticipantInput(ticketTypeId: ticketId, categoryId: cat.id);
    _self.applyTo(p);
    setState(() {
      _ticketId = ticketId;
      _me = p;
      _accepted = false;
      _refusal = null;
      _showRegister = false;
      _serverProblems.clear();
    });
    _loadFields();
  }

  bool get _anyMinAge =>
      _detail?.categories.any((c) => c.minAge != null) ?? false;

  ParticipantFields get _effectiveFields =>
      _fields ?? ParticipantFields.defaultsFor(anyMinAge: _anyMinAge);

  /// The fields and consent text come from the checkout quote, so the join
  /// asks exactly what a purchase would. A failed quote keeps the defaults.
  Future<void> _loadFields() async {
    final d = _detail;
    final me = _me;
    if (d == null || me == null) return;
    try {
      final res = await _api.quoteEventOrder(
        registrationBody(
          eventId: d.id,
          lines: {me.ticketTypeId: 1},
          participants: [me],
          fields: _effectiveFields,
        ),
      );
      if (!mounted) return;
      final q = EventQuote.fromJson(res, anyMinAge: _anyMinAge);
      setState(() {
        _fields = q.fields;
        _consent = q.consentText;
      });
    } catch (_) {
      // The defaults stand; the server checks the details on join.
    }
  }

  Map<String, FieldProblem> _problems() {
    final d = _detail;
    final me = _me;
    if (d == null || me == null) return const {};
    final cat = _categoryOf(d, me.ticketTypeId);
    final local = validateParticipantLocally(
      me,
      fields: _effectiveFields,
      minAge: cat?.minAge,
      eventStartUtc: d.summary.startsAt,
      offsetMinutes: d.summary.utcOffsetMinutes,
      now: _now,
    );
    return {..._serverProblems, ...local};
  }

  bool get _canJoin =>
      _me != null &&
      _accepted &&
      !_joining &&
      _self.hasVerifiedContact &&
      _problems().isEmpty;

  String get _consentVersion => _consent.version.isNotEmpty
      ? _consent.version
      : _options.consentTextVersion;

  Future<void> _join() async {
    final d = _detail;
    final me = _me;
    if (d == null || me == null || !_canJoin) return;
    final body = waitlistJoinBody(
      ticketTypeId: me.ticketTypeId,
      participant: me.toJson(_effectiveFields),
      consentTextVersion: _consentVersion,
      locale: FFLocaleScope.of(context).locale.languageCode,
    );
    _attempt = CheckoutAttempt.forPurchase(
      _attempt,
      registrationSignature(body),
    );
    final locale = FFLocaleScope.of(context);
    final snack = FFSnack.of(context);
    setState(() {
      _joining = true;
      _refusal = null;
    });
    try {
      final res = await _api.joinEventWaitlist(
        d.id,
        body,
        idempotencyKey: _attempt!.key,
      );
      if (!mounted) return;
      final entry = WaitlistEntry.fromJson(
        res['entry'] is Map ? res['entry'] as Map : res,
      );
      setState(() {
        _joining = false;
        _joined = entry;
      });
      _focusHeading();
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      if (isNetworkError(e)) {
        snack.error(locale.t('events.waitlist.offline'));
        return;
      }
      if (e is ApiException) {
        if (e.code == 'validation_failed') {
          final fields = e.body is Map ? (e.body as Map)['fields'] : null;
          setState(() {
            _serverProblems.clear();
            if (fields is List) {
              for (final f in fields) {
                if (f is Map) {
                  final p = FieldProblem.fromJson(f);
                  _serverProblems[p.field] = p;
                }
              }
            }
            _refusal = locale.t('events.review.fix');
          });
          return;
        }
        if (e.code == 'consent_required') {
          setState(() {
            _accepted = false;
            _refusal = locale.t('events.review.accept');
          });
          return;
        }
        if (e.code == 'not_sold_out') {
          setState(() {
            _refusal = locale.t('events.waitlist.error.not_sold_out');
            _showRegister = true;
          });
          return;
        }
        setState(() => _refusal = waitlistErrorMessage(locale, e));
        return;
      }
      snack.error(waitlistErrorMessage(locale, e));
    }
  }

  Future<void> _editProfile() async {
    final me = context
        .dependOnInheritedWidgetOfExactType<MemberDataScope>()
        ?.notifier
        ?.me;
    if (me == null) return;
    await openMemberEditProfile(context, me);
    if (mounted) setState(() {});
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventDetailPath(widget.eventId));

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.waitlist.join.title')),
      ),
      body: _gated
          ? const SizedBox.shrink()
          : _loading
          ? Center(
              child: FFSkeletonList(
                key: const Key('waitlist-join-loading'),
                semanticLabel: context.tr('common.loading'),
              ),
            )
          : _gone
          ? Center(
              child: FFEmptyState(
                key: const Key('waitlist-join-gone'),
                icon: Icons.event_busy_outlined,
                title: context.tr('events.detail.gone.title'),
                body: context.tr('events.detail.gone.body'),
              ),
            )
          : d == null
          ? Center(
              child: FFErrorState(
                key: const Key('waitlist-join-error'),
                message: _error == null
                    ? null
                    : errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : _joined != null
          ? _success(context, d, _joined!)
          : _form(context, d),
      bottomNavigationBar: d == null || _joined != null || _loading
          ? null
          : _bottomBar(context),
    );
  }

  Widget _title(BuildContext context, EventDetail d, {String? sub}) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _heading,
      child: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.title,
              key: const Key('waitlist-join-event'),
              style: tt.titleLarge,
            ),
            if (sub != null)
              Text(
                sub,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _frame(List<Widget> children) => ListView(
    key: const Key('waitlist-join-scroll'),
    padding: const EdgeInsets.all(FFTokens.spacingMd),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              const SizedBox(height: FFTokens.spacingXl),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _form(BuildContext context, EventDetail d) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final me = _me;
    final ticket = me == null ? null : _ticket(d, me.ticketTypeId);
    final cat = me == null ? null : _categoryOf(d, me.ticketTypeId);
    final types = _ticketTypes(d);
    final price = ticket == null
        ? ''
        : ticket.isFree
        ? context.tr('events.card.free')
        : formatCurrency(ticket.priceTzs, currency: ticket.currency);
    return _frame([
      _title(context, d, sub: context.tr('events.waitlist.join.pickTicket')),
      const SizedBox(height: FFTokens.spacingMd),
      RadioGroup<String>(
        groupValue: _ticketId,
        onChanged: (v) {
          if (v != null) _pick(v);
        },
        child: Column(
          children: [
            for (final t in types)
              Builder(
                builder: (context) {
                  final open = t.canJoinWaitlist;
                  final reason = open
                      ? null
                      : (t.availability == EventAvailability.open ||
                            t.availability == EventAvailability.closingSoon)
                      ? context.tr('events.waitlist.error.not_sold_out')
                      : context.tr('events.waitlist.error.unavailable');
                  final priceLine = t.isFree
                      ? context.tr('events.card.free')
                      : formatCurrency(t.priceTzs, currency: t.currency);
                  return RadioListTile<String>(
                    key: Key('waitlist-ticket-${t.id}'),
                    value: t.id,
                    enabled: open,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${t.name} · $priceLine'),
                    subtitle: reason == null ? null : Text(reason),
                  );
                },
              ),
          ],
        ),
      ),
      if (me != null && cat != null) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFSectionTitle(context.tr('events.waitlist.join.details')),
        ParticipantForm(
          key: ValueKey('wl-pf-${me.ticketTypeId}'),
          index: 0,
          total: 1,
          participant: me,
          fields: _effectiveFields,
          category: cat,
          ticketName: ticket?.name ?? '',
          problems: _problems(),
          expanded: true,
          onToggle: () {},
          onChanged: () {
            _serverProblems.clear();
            setState(() {});
          },
          consentText: _consent.of(consentSelf).of(lang),
          selfHasVerifiedContact: _self.hasVerifiedContact,
          onEditProfile: _editProfile,
        ),
        if (!_self.hasVerifiedContact)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('waitlist-verify'),
              tone: FFAlertTone.warning,
              message: context.tr('events.waitlist.error.verification'),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('events.waitlist.join.one'),
          key: const Key('waitlist-one'),
          style: tt.bodyMedium,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          context
              .tr('events.waitlist.join.price')
              .replaceFirst('{amount}', price),
          key: const Key('waitlist-price'),
          style: tt.titleSmall,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFAlert(
          key: const Key('waitlist-rules'),
          tone: FFAlertTone.info,
          message: context
              .tr('events.waitlist.join.rules')
              .replaceFirst('{hours}', '${_options.waitlist.offerHours}'),
        ),
        if (d.terms.isNotEmpty)
          FFCard(
            key: const Key('waitlist-terms'),
            margin: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                context.tr('events.review.terms'),
                style: tt.bodyMedium,
              ),
              children: [Text(d.terms.of(lang), style: tt.bodySmall)],
            ),
          ),
        Semantics(
          container: true,
          child: CheckboxListTile(
            key: const Key('waitlist-accept'),
            value: _accepted,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              context.tr('events.review.accept'),
              style: tt.bodyMedium,
            ),
            onChanged: (v) => setState(() => _accepted = v ?? false),
          ),
        ),
      ],
      if (_refusal != null)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('waitlist-refusal'),
              tone: FFAlertTone.error,
              message: _refusal!,
            ),
          ),
        ),
      if (_showRegister)
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('waitlist-register-instead'),
            label: context.tr('events.cta.register'),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            onPressed: () => context.pushReplacement(
              AppRoutes.memberEventRegisterPath(d.id, ticket: _ticketId),
            ),
          ),
        ),
      if (_ticketId == null)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: Text(
            context.tr('events.waitlist.cta.hint'),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
    ]);
  }

  Widget _success(BuildContext context, EventDetail d, WaitlistEntry e) {
    final tt = Theme.of(context).textTheme;
    return _frame([
      _title(context, d),
      const SizedBox(height: FFTokens.spacingLg),
      Icon(
        Icons.check_circle_outline,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: FFTokens.spacingSm),
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(
          context.tr('events.waitlist.joined.title'),
          key: const Key('waitlist-joined-title'),
          style: tt.headlineSmall,
          textAlign: TextAlign.center,
        ),
      ),
      if (e.position != null)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: Semantics(
            label: context
                .tr('events.waitlist.sem.position')
                .replaceFirst('{n}', '${e.position}'),
            child: ExcludeSemantics(
              child: Text(
                context
                    .tr('events.waitlist.joined.position')
                    .replaceFirst('{n}', '${e.position}'),
                key: const Key('waitlist-joined-position'),
                style: tt.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      const SizedBox(height: FFTokens.spacingSm),
      Text(
        context.tr('events.waitlist.joined.body'),
        key: const Key('waitlist-joined-body'),
        style: tt.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: FFTokens.spacingLg),
      FFButton(
        key: const Key('waitlist-joined-view'),
        label: context.tr('events.waitlist.joined.view'),
        fullWidth: true,
        onPressed: () => context.pushReplacement(AppRoutes.memberEventWaitlist),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFButton(
        key: const Key('waitlist-joined-back'),
        label: context.tr('events.waitlist.joined.back'),
        variant: FFButtonVariant.secondary,
        fullWidth: true,
        onPressed: () =>
            context.pushReplacement(AppRoutes.memberEventDetailPath(d.id)),
      ),
    ]);
  }

  Widget _bottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('waitlist-join-bar'),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outline)),
        ),
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: FFButton(
              key: const Key('waitlist-join'),
              label: _joining
                  ? context.tr('events.waitlist.join.busy')
                  : context.tr('events.waitlist.join.button'),
              fullWidth: true,
              loading: _joining,
              onPressed: _canJoin ? _join : null,
            ),
          ),
        ),
      ),
    );
  }
}
