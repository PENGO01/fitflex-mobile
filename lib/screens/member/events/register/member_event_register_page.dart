import 'dart:async';

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
import '../../../../shared/events/registration_draft.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/shop_checkout.dart';
import '../../member_edit_profile_page.dart';
import '../../member_shell.dart';
import '../events_registration_gate.dart';
import 'participant_form.dart';
import 'quote_summary.dart';
import 'registration_mode_tiles.dart';
import 'self_profile.dart';
import 'ticket_picker.dart';

/// `/member/events/:eventId/register` (events S3 spec §5.2–§5.6): four
/// steps in one page — Tickets, Who, Participants, Review — ending in
/// `POST /me/event-orders` with an `Idempotency-Key`.
class MemberEventRegisterPage extends StatefulWidget {
  const MemberEventRegisterPage({
    super.key,
    required this.eventId,
    this.preselectTicketId,
    this.source = 'cta',
    this.options,
    this.selfProfile,
    this.now,
    this.draftDebounce = const Duration(milliseconds: 500),
  });

  final String eventId;

  /// A ticket row tap on the detail preselects this type at its minimum.
  final String? preselectTicketId;
  final String source;
  final EventsOptions? options;

  /// Injectable "Myself" prefill (tests); read from the scopes when absent.
  final RegistrationSelfProfile? selfProfile;
  final DateTime? now;
  final Duration draftDebounce;

  @override
  State<MemberEventRegisterPage> createState() =>
      _MemberEventRegisterPageState();
}

class _MemberEventRegisterPageState extends State<MemberEventRegisterPage> {
  EventDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _gone = false;

  int _step = 1;
  Map<String, int> _lines = {};
  RegistrationWho _who = const RegistrationWho();
  List<EventParticipantInput> _participants = [];
  ParticipantFields? _fields;
  ConsentText _consent = const ConsentText();
  final Set<int> _expanded = {0};
  final Map<int, Map<String, FieldProblem>> _serverProblems = {};

  EventQuote? _quote;
  bool _quoteLoading = false;
  Object? _quoteError;
  bool _accepted = false;
  bool _placing = false;
  CheckoutAttempt? _attempt;
  String? _banner;
  String? _bannerTicket;
  int? _bannerLeft;

  Timer? _draftTimer;
  bool _dirty = false;
  bool _draftChecked = false;
  bool _gated = false;

  final _heading = FocusNode(debugLabel: 'register-step-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);
  RegistrationSelfProfile get _self =>
      widget.selfProfile ?? RegistrationSelfProfile.fromScope(context);
  DateTime get _now => widget.now ?? DateTime.now();

  int get _places => _lines.values.fold(0, (a, b) => a + b);
  bool get _anyMinAge =>
      _detail?.categories.any((c) => c.minAge != null) ?? false;
  ParticipantFields get _effectiveFields =>
      _fields ?? ParticipantFields.defaultsFor(anyMinAge: _anyMinAge);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
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
      final cached = await EventsCache.getDetail(widget.eventId);
      Map<String, dynamic> json;
      if (cached != null) {
        json = cached.$2;
      } else {
        json = await _api.getEvent(widget.eventId);
        EventsCache.putDetail(widget.eventId, json);
      }
      if (!mounted) return;
      final d = EventDetail.fromJson(json);
      setState(() {
        _detail = d;
        _loading = false;
      });
      EventsAnalytics.registrationStarted(eventId: d.id, source: widget.source);
      _applyPreselect(d);
      await _offerDraft(d);
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

  void _applyPreselect(EventDetail d) {
    final id = widget.preselectTicketId;
    if (id == null || _lines.isNotEmpty) return;
    for (final c in d.categories) {
      for (final t in c.ticketTypes) {
        if (t.id == id && TicketPicker.onSale(t)) {
          setState(() => _lines = {id: t.minPerOrder > 0 ? t.minPerOrder : 1});
          EventsAnalytics.registrationStarted(
            eventId: d.id,
            source: 'ticket_row',
          );
        }
      }
    }
  }

  // ── draft (§5.5) ───────────────────────────────────────────────────────

  Future<void> _offerDraft(EventDetail d) async {
    if (_draftChecked) return;
    _draftChecked = true;
    final draft = await RegistrationDraftStore.load(d.id);
    if (draft == null || !mounted) return;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final resume = await showFFConfirmDialog(
      context,
      title: context.tr('events.draft.resume.title'),
      message: context
          .tr('events.draft.resume.body')
          .replaceFirst('{event}', d.title)
          .replaceFirst('{date}', formatDate(draft.savedAt, locale: lang)),
      confirmLabel: context.tr('events.draft.resume.continue'),
      cancelLabel: context.tr('events.draft.resume.discard'),
      confirmKey: const Key('draft-continue'),
      cancelKey: const Key('draft-discard'),
      barrierDismissible: false,
    );
    if (!mounted) return;
    if (!resume) {
      await RegistrationDraftStore.clear(d.id);
      return;
    }
    setState(() {
      _lines = Map.of(draft.lines);
      _participants = List.of(draft.participants);
      _who = RegistrationWho(
        mode: registrationModes.contains(draft.mode) ? draft.mode : 'self',
        teamOn: draft.team != null,
        teamMode: draft.team?.isCreate == false ? 'join' : 'create',
        teamName: draft.team?.name ?? '',
        teamType: draft.team?.teamType ?? 'community',
        teamCode: draft.team?.joinCode ?? '',
      );
      _step = draft.step.clamp(1, 3);
      if (_step == 3) _rebuildParticipants();
    });
    if (_step == 3) _loadFields();
  }

  void _touch() {
    _dirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(widget.draftDebounce, _saveDraft);
  }

  Future<void> _saveDraft() async {
    final d = _detail;
    if (d == null || !_dirty) return;
    await RegistrationDraftStore.save(
      RegistrationDraft(
        eventId: d.id,
        savedAt: _now.toUtc(),
        step: _step,
        lines: _lines,
        mode: _who.mode,
        team: _who.team,
        participants: _participants,
      ),
    );
  }

  // ── steps ──────────────────────────────────────────────────────────────

  void _focusHeading() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _heading.requestFocus();
  });

  void _goTo(int step) {
    final from = _step;
    setState(() {
      _step = step;
      _banner = null;
    });
    _touch();
    _focusHeading();
    // Entering Participants from Tickets / Who rebuilds the cards for the
    // chosen lines and mode; coming back from Review keeps them (and the
    // server's problems) as they are.
    if (step == 3 && from < 3) {
      _rebuildParticipants();
      _loadFields();
    }
    if (step == 4) {
      // A fresh look at Review means a fresh acceptance of the terms.
      _accepted = false;
      _loadQuote();
    }
  }

  List<({String ticketTypeId, EventCategory category, String ticketName})>
  _slots() {
    final d = _detail!;
    final out =
        <({String ticketTypeId, EventCategory category, String ticketName})>[];
    for (final c in d.categories) {
      for (final t in c.ticketTypes) {
        for (var i = 0; i < (_lines[t.id] ?? 0); i++) {
          out.add((ticketTypeId: t.id, category: c, ticketName: t.name));
        }
      }
    }
    return out;
  }

  void _rebuildParticipants() {
    final slots = _slots();
    final next = <EventParticipantInput>[];
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final existing = i < _participants.length ? _participants[i] : null;
      final p = existing != null && existing.ticketTypeId == s.ticketTypeId
          ? existing
          : EventParticipantInput(
              ticketTypeId: s.ticketTypeId,
              categoryId: s.category.id,
            );
      final self = _who.mode != 'others' && i == 0;
      if (self) {
        _self.applyTo(p);
      } else if (p.isSelf) {
        p
          ..isSelf = false
          ..phone = ''
          ..email = ''
          ..consented = false;
      }
      next.add(p);
    }
    _participants = next;
    _serverProblems.clear();
    _expanded
      ..clear()
      ..add(0);
    setState(() {});
  }

  Future<void> _loadFields() async {
    final d = _detail;
    if (d == null) return;
    try {
      final res = await _api.quoteEventOrder(_quoteBody());
      if (!mounted) return;
      final q = EventQuote.fromJson(res, anyMinAge: _anyMinAge);
      setState(() {
        _fields = q.fields;
        _consent = q.consentText;
      });
    } catch (_) {
      // The form falls back to the spec defaults until step 4 quotes.
    }
  }

  Map<String, dynamic> _quoteBody() => registrationBody(
    eventId: _detail!.id,
    lines: _lines,
    participants: _participants,
    fields: _effectiveFields,
    team: _who.team,
  );

  Future<void> _loadQuote() async {
    final d = _detail;
    if (d == null) return;
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final res = await _api.quoteEventOrder(_quoteBody());
      if (!mounted) return;
      final q = EventQuote.fromJson(res, anyMinAge: _anyMinAge);
      setState(() {
        _quote = q;
        _fields = q.fields;
        _consent = q.consentText;
        _quoteLoading = false;
        _serverProblems
          ..clear()
          ..addAll({
            for (final e in q.participantProblems.entries)
              e.key: {for (final p in e.value) p.field: p},
          });
        if (_serverProblems.isNotEmpty) _banner = 'fix';
        for (final e in q.availability.entries) {
          final a = e.value;
          if (a.availability == EventAvailability.soldOut ||
              (a.remaining != null && a.remaining! < (_lines[e.key] ?? 0))) {
            _banner = 'onlyLeft';
            _bannerTicket = _ticketName(e.key);
            // Only a real count is shown; sold out / unknown reads
            // "no longer available".
            _bannerLeft = a.remaining;
          }
        }
      });
      EventsAnalytics.quoteCreated(
        eventId: d.id,
        placesCount: _places,
        totalTzs: q.totalTzs,
        mode: _who.mode,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteLoading = false;
        _quoteError = e;
      });
    }
  }

  String _ticketName(String ticketTypeId) {
    for (final c in _detail?.categories ?? const <EventCategory>[]) {
      for (final t in c.ticketTypes) {
        if (t.id == ticketTypeId) return t.name;
      }
    }
    return ticketTypeId;
  }

  Map<String, FieldProblem> _problemsFor(int i, Set<int> twice) {
    final d = _detail!;
    final p = _participants[i];
    final cat = d.categories.firstWhere(
      (c) => c.id == p.categoryId,
      orElse: () => const EventCategory(id: '', name: ''),
    );
    final local = validateParticipantLocally(
      p,
      fields: _effectiveFields,
      minAge: cat.minAge,
      eventStartUtc: d.summary.startsAt,
      offsetMinutes: d.summary.utcOffsetMinutes,
      now: _now,
    );
    if (twice.contains(i)) {
      local.putIfAbsent(
        'phone',
        () => const FieldProblem(field: 'phone', code: 'listed_twice'),
      );
    }
    return {...?_serverProblems[i], ...local};
  }

  bool get _participantsClean {
    if (_participants.isEmpty) return false;
    final twice = listedTwice(_participants);
    for (var i = 0; i < _participants.length; i++) {
      if (_problemsFor(i, twice).isNotEmpty) return false;
      if (_participants[i].isSelf && !_self.hasVerifiedContact) return false;
    }
    return true;
  }

  // ── place order (§5.6) ─────────────────────────────────────────────────

  Map<String, dynamic> _orderBody(EventQuote q) => {
    ..._quoteBody(),
    'acceptedTerms': true,
    'consentTextVersion': q.consentText.version.isNotEmpty
        ? q.consentText.version
        : _options.consentTextVersion,
    'expectedTotalTzs': q.totalTzs,
  };

  Future<void> _place({bool retried = false}) async {
    final q = _quote;
    final d = _detail;
    if (q == null || d == null || _placing || !_accepted) return;
    final body = _orderBody(q);
    _attempt = CheckoutAttempt.forPurchase(
      _attempt,
      registrationSignature(body),
    );
    setState(() {
      _placing = true;
      _banner = null;
    });
    final locale = FFLocaleScope.of(context);
    final snack = FFSnack.of(context);
    try {
      final res = await _api.createEventOrder(
        body,
        idempotencyKey: _attempt!.key,
      );
      if (!mounted) return;
      final order = EventOrderDetail.fromJson(res);
      EventsAnalytics.orderCreated(
        orderId: order.order.id,
        eventId: d.id,
        placesCount: _places,
        totalTzs: order.order.totalTzs,
        mode: _who.mode,
        team: _who.team != null,
      );
      _dirty = false;
      _draftTimer?.cancel();
      await RegistrationDraftStore.clear(d.id);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.memberEventOrder(order.order.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
      switch (e.code) {
        case 'price_changed':
          await _loadQuote();
          if (mounted) setState(() => _banner = 'priceChanged');
        case 'capacity_unavailable':
          final id = e.body is Map
              ? (e.body as Map)['ticketTypeId']?.toString()
              : null;
          setState(() {
            _banner = 'onlyLeft';
            _bannerTicket = id == null ? '' : _ticketName(id);
            _bannerLeft = e.body is Map && (e.body as Map)['remaining'] is num
                ? ((e.body as Map)['remaining'] as num).toInt()
                : null;
          });
        case 'participant_invalid':
          setState(() {
            _serverProblems
              ..clear()
              ..addAll({
                for (final en in ParticipantCheck.byIndex(
                  e.body is Map ? (e.body as Map)['participants'] : null,
                ).entries)
                  en.key: {for (final p in en.value) p.field: p},
              });
            _banner = 'fix';
          });
        case 'consent_version_stale' when !retried:
          await _loadQuote();
          if (mounted && _quote != null) await _place(retried: true);
        case 'idempotency_key_reused' when !retried:
          _attempt = null;
          await _place(retried: true);
        default:
          if (eventOrderOutcomeUnknown(e)) {
            await _uncertain();
          } else {
            snack.error(eventsErrorMessage(locale, e));
          }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
      if (eventOrderOutcomeUnknown(e)) {
        await _uncertain();
      } else {
        snack.error(eventsErrorMessage(locale, e));
      }
    }
  }

  Future<void> _uncertain() async {
    final again = await showFFConfirmDialog(
      context,
      title: context.tr('events.review.uncertain.title'),
      message: context.tr('events.review.uncertain.body'),
      confirmLabel: context.tr('events.review.tryAgain'),
      cancelLabel: context.tr('events.review.openMine'),
      confirmKey: const Key('uncertain-retry'),
      cancelKey: const Key('uncertain-open-mine'),
      barrierDismissible: false,
    );
    if (!mounted) return;
    if (again) {
      await _place();
    } else {
      context.go(AppRoutes.memberEventOrders);
    }
  }

  // ── navigation ─────────────────────────────────────────────────────────

  Future<void> _leave() async {
    if (_dirty) {
      _draftTimer?.cancel();
      await _saveDraft();
      if (mounted) FFSnack.info(context, context.tr('events.draft.saved'));
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.memberEventDetailPath(widget.eventId));
    }
  }

  void _back() {
    if (_step > 1) {
      _goTo(_step - 1);
    } else {
      _leave();
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

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final stepName = context.tr(
      'events.register.step.${const ['tickets', 'who', 'participants', 'review'][_step - 1]}',
    );
    final subtitle = context
        .tr('events.register.step')
        .replaceFirst('{n}', '$_step')
        .replaceFirst('{name}', stepName);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.tr('a11y.back'),
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(context.tr('events.register.title')),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              key: const Key('register-progress'),
              value: _step / 4,
              minHeight: 4,
              semanticsLabel: subtitle,
            ),
          ),
        ),
        body: _gated
            ? const SizedBox.shrink()
            : _loading
            ? Center(
                child: FFSkeletonList(
                  key: const Key('register-loading'),
                  semanticLabel: context.tr('common.loading'),
                ),
              )
            : _gone
            ? Center(
                child: FFEmptyState(
                  key: const Key('register-gone'),
                  icon: Icons.event_busy_outlined,
                  title: context.tr('events.detail.gone.title'),
                  body: context.tr('events.detail.gone.body'),
                ),
              )
            : d == null
            ? Center(
                child: FFErrorState(
                  key: const Key('register-error'),
                  message: _error == null
                      ? null
                      : errorMessage(FFLocaleScope.of(context), _error!),
                  retryLabel: context.tr('common.retry'),
                  onRetry: _load,
                ),
              )
            : _body(context, d, subtitle),
        bottomNavigationBar: d == null ? null : _bottomBar(context),
      ),
    );
  }

  Widget _body(BuildContext context, EventDetail d, String subtitle) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final Widget content = switch (_step) {
      1 => TicketPicker(
        key: const Key('register-step-1'),
        detail: d,
        lines: _lines,
        maxParticipants: _options.maxParticipantsPerOrder,
        onChanged: (v) {
          setState(() => _lines = v);
          _touch();
        },
      ),
      2 => RegistrationModeTiles(
        key: const Key('register-step-2'),
        eventId: d.id,
        places: _places,
        value: _who,
        teamsEnabled: _options.teams,
        corporateEnabled: _options.corporate,
        onChanged: (v) {
          setState(() => _who = v);
          _touch();
        },
      ),
      3 => _participantsStep(context, d),
      _ => _reviewStep(context, d),
    };
    return ListView(
      key: const Key('register-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  focusNode: _heading,
                  child: Semantics(
                    header: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.title,
                          key: const Key('register-event-title'),
                          style: tt.titleLarge,
                        ),
                        Text(
                          subtitle,
                          key: const Key('register-step-subtitle'),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                content,
                const SizedBox(height: FFTokens.spacingXl),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _participantsStep(BuildContext context, EventDetail d) {
    final slots = _slots();
    final twice = listedTwice(_participants);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final selfIndex = _participants.indexWhere((p) => p.isSelf);
    final selfHasEmergency =
        selfIndex >= 0 && _participants[selfIndex].hasEmergencyContact;
    return Column(
      key: const Key('register-step-3'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _participants.length && i < slots.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: ParticipantForm(
              key: ValueKey('pf-$i-${_participants[i].ticketTypeId}'),
              index: i,
              total: _participants.length,
              participant: _participants[i],
              fields: _effectiveFields,
              category: slots[i].category,
              ticketName: slots[i].ticketName,
              problems: _problemsFor(i, twice),
              expanded: _expanded.contains(i),
              consentText: _consent.of(consentPurchaserAuthorised).of(lang),
              selfHasVerifiedContact: _self.hasVerifiedContact,
              onEditProfile: _editProfile,
              onCopyEmergency: !_participants[i].isSelf && selfHasEmergency
                  ? () => setState(() {
                      _participants[i]
                        ..emergencyName = _participants[selfIndex].emergencyName
                        ..emergencyPhone =
                            _participants[selfIndex].emergencyPhone;
                      _touch();
                    })
                  : null,
              onToggle: () => setState(() {
                if (!_expanded.remove(i)) _expanded.add(i);
              }),
              onChanged: () {
                _serverProblems.remove(i);
                setState(() {});
                _touch();
              },
            ),
          ),
      ],
    );
  }

  Widget _reviewStep(BuildContext context, EventDetail d) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final q = _quote;
    final children = <Widget>[];
    if (_banner != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: _bannerWidget(context),
        ),
      );
    }
    if (!_quoteLoading && q != null) {
      final issues = _quoteIssues(context, q);
      if (issues.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Semantics(
              liveRegion: true,
              child: FFAlert(
                key: const Key('review-quote-issues'),
                tone: FFAlertTone.error,
                message: issues.join('\n'),
              ),
            ),
          ),
        );
      }
    }
    if (_quoteLoading) {
      children.add(
        Semantics(
          label: context.tr('common.loading'),
          container: true,
          child: const Column(
            key: Key('review-loading'),
            children: [
              FFSkeletonLine(),
              SizedBox(height: FFTokens.spacingSm),
              FFSkeletonLine(),
              SizedBox(height: FFTokens.spacingSm),
              FFSkeletonLine(widthFactor: 0.7),
              SizedBox(height: FFTokens.spacingSm),
              FFSkeletonLine(widthFactor: 0.5),
            ],
          ),
        ),
      );
    } else if (q == null) {
      children.add(
        FFErrorState(
          key: const Key('review-error'),
          message: _quoteError == null
              ? null
              : errorMessage(FFLocaleScope.of(context), _quoteError!),
          retryLabel: context.tr('common.retry'),
          onRetry: _loadQuote,
        ),
      );
    } else {
      final slots = _slots();
      final anyOther = _participants.any((p) => !p.isSelf);
      final teamLabel = switch (_who.team) {
        null => null,
        final t when t.isCreate =>
          '${t.name} · ${context.tr('events.team.type.${t.teamType}')}',
        _ => _who.teamFound?.name ?? formatTeamCode(_who.teamCode),
      };
      children.add(
        QuoteSummary(
          quote: q,
          detail: d,
          participants: [
            for (var i = 0; i < _participants.length; i++)
              (
                name: [
                  _participants[i].firstName,
                  _participants[i].lastName,
                ].where((s) => s.trim().isNotEmpty).join(' '),
                category: i < slots.length ? slots[i].category.name : '',
                isSelf: _participants[i].isSelf,
              ),
          ],
          accepted: _accepted,
          onAccepted: (v) => setState(() => _accepted = v),
          holdTtlMinutes: q.holdTtlMinutes,
          teamLabel: teamLabel,
          consentLine: anyOther
              ? _consent.of(consentPurchaserAuthorised).of(lang)
              : null,
        ),
      );
    }
    return Column(
      key: const Key('register-step-4'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// What the quote says is wrong at order level (§3.4 `problems[]`,
  /// `team.problems`): sale closed, team full, team name taken, too many
  /// participants, capacity short. A quote that is not `valid` and has
  /// nothing else to say still gets one line, so the disabled button is
  /// never unexplained. Participant-level problems have their own banner.
  List<String> _quoteIssues(BuildContext context, EventQuote q) {
    final locale = FFLocaleScope.of(context);
    final seen = <String>{};
    final out = <String>[];
    void add(String code, Map<String, dynamic>? extra) {
      if (code.isEmpty || !seen.add(code)) return;
      // Capacity already has its own banner with the change-tickets action.
      if (_banner == 'onlyLeft' &&
          (code == 'capacity_unavailable' || code == 'capacity_short')) {
        return;
      }
      out.add(errorReasonText(locale, code, extra));
    }

    for (final p in q.problems) {
      add(p.code, p.extra);
    }
    for (final code in q.team?.problems ?? const <String>[]) {
      add(code, null);
    }
    if (!q.valid &&
        out.isEmpty &&
        _banner != 'fix' &&
        _banner != 'onlyLeft' &&
        q.participantProblems.isEmpty) {
      out.add(context.tr('events.review.problems'));
    }
    return out;
  }

  Widget _bannerWidget(BuildContext context) {
    switch (_banner) {
      case 'priceChanged':
        return FFAlert(
          key: const Key('review-banner-price'),
          tone: FFAlertTone.warning,
          message: context.tr('events.review.priceChanged'),
        );
      case 'onlyLeft':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FFAlert(
              key: const Key('review-banner-capacity'),
              tone: FFAlertTone.warning,
              message: _bannerLeft == null
                  ? context.tr('events.review.unavailable')
                  : context
                        .tr('events.review.onlyLeft')
                        .replaceFirst('{n}', '$_bannerLeft')
                        .replaceFirst('{ticket}', _bannerTicket ?? ''),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('review-change-tickets'),
                label: context.tr('events.review.changeTickets'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                onPressed: () => _goTo(1),
              ),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: FFAlert(
                key: const Key('review-banner-fix'),
                tone: FFAlertTone.error,
                message: context.tr('events.review.fix'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('review-go-back'),
                label: context.tr('events.review.goBack'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                onPressed: () {
                  final first = _serverProblems.keys.isEmpty
                      ? 0
                      : _serverProblems.keys.reduce((a, b) => a < b ? a : b);
                  _expanded
                    ..clear()
                    ..add(first);
                  _goTo(3);
                },
              ),
            ),
          ],
        );
    }
  }

  Widget _bottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _quote;
    String label;
    VoidCallback? onPressed;
    switch (_step) {
      case 1:
        label = context.tr('events.register.continue');
        onPressed = _places >= 1 ? () => _goTo(2) : null;
      case 2:
        label = context.tr('events.register.continue');
        onPressed = _who.teamIncomplete ? null : () => _goTo(3);
      case 3:
        label = context.tr('events.register.review');
        onPressed = _participantsClean ? () => _goTo(4) : null;
      default:
        label = q == null
            ? context.tr('events.register.place').replaceFirst('{amount}', '')
            : q.isFree
            ? context.tr('events.register.placeFree')
            : context
                  .tr('events.register.place')
                  .replaceFirst(
                    '{amount}',
                    formatCurrency(q.totalTzs, currency: q.currency),
                  );
        onPressed =
            q != null &&
                q.valid &&
                _accepted &&
                !_quoteLoading &&
                _banner != 'fix'
            ? _place
            : null;
    }
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('register-bottom-bar'),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outline)),
        ),
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Row(
              children: [
                if (_step > 1) ...[
                  FFButton(
                    key: const Key('register-back'),
                    label: context.tr('events.register.back'),
                    variant: FFButtonVariant.ghost,
                    onPressed: _placing ? null : _back,
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                ],
                Expanded(
                  child: FFButton(
                    key: const Key('register-primary'),
                    label: label,
                    fullWidth: true,
                    loading: _placing,
                    onPressed: onPressed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
