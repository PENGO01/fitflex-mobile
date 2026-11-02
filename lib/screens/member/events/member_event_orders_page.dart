import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_cache.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/events/waitlist.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import 'event_status.dart';
import 'events_registration_gate.dart';
import 'pay/event_payment_cards.dart';
import 'tickets/member_event_tickets_view.dart';
import 'waitlist/member_event_waitlist_view.dart';

/// Where "Not me" dismissals are remembered on this device (§5.8).
const kDismissedClaimsKey = 'events.claim.dismissed';

/// `/member/events/orders` (events S3 spec §5.8, S4 spec §5.4): Tickets |
/// Registrations | Orders. The Tickets segment is there while the server
/// says tickets carry a QR, and is first when the member holds a ticket.
class MemberEventOrdersPage extends StatefulWidget {
  const MemberEventOrdersPage({
    super.key,
    this.initialTab = '',
    this.options,
    this.now,
  });

  /// `tickets` | `registrations` (default) | `orders`. Empty picks Tickets
  /// when the member has an active ticket, else Registrations.
  final String initialTab;
  final EventsOptions? options;
  final DateTime? now;

  static const pageSize = 20;

  @override
  State<MemberEventOrdersPage> createState() => _MemberEventOrdersPageState();
}

class _MemberEventOrdersPageState extends State<MemberEventOrdersPage> {
  String _tab = '';
  EventTicketsController? _ticketsCtl;
  EventTicketsController get _tickets => _ticketsCtl!;
  WaitlistController? _waitlistCtl;
  final _regs = _PagedList<EventRegistration>();
  final _orders = _PagedList<EventOrder>();
  List<ClaimPreview> _claimable = [];
  Set<String> _dismissed = {};
  bool _started = false;
  final _scroll = ScrollController();

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  bool get _qr => _options.tickets.qr;

  /// Events S7: the Waitlist segment shows only while the server has it on.
  bool get _waitlist => _options.waitlist.enabled;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'orders' ? 'orders' : 'registrations';
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ticketsCtl?.dispose();
    _waitlistCtl?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    _ticketsCtl = EventTicketsController(api: _api);
    if (_waitlist) {
      _waitlistCtl = WaitlistController(api: _api);
      if (widget.initialTab == 'waitlist') _tab = 'waitlist';
    }
    _started = true;
    await _loadDismissed();
    await Future.wait([
      if (_waitlist) _waitlistCtl!.load(),
      _loadRegistrations(),
      _loadOrders(),
      if (_qr) _loadTickets(),
    ]);
  }

  /// Loads the wallet and settles the first tab: an explicit one from the
  /// route, else Tickets when there is an active ticket.
  Future<void> _loadTickets() async {
    await _tickets.load();
    if (!mounted) return;
    setState(() {
      if (widget.initialTab == 'tickets') {
        _tab = 'tickets';
      } else if (widget.initialTab.isEmpty && _tickets.hasActive) {
        _tab = 'tickets';
      }
    });
  }

  Future<void> _loadDismissed() async {
    try {
      final p = await SharedPreferences.getInstance();
      _dismissed = (p.getStringList(kDismissedClaimsKey) ?? []).toSet();
    } catch (_) {}
  }

  Future<void> _dismiss(String id) async {
    setState(() => _dismissed.add(id));
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(kDismissedClaimsKey, _dismissed.toList());
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 300) {
      if (_tab == 'tickets') {
        _tickets.loadMore();
      } else if (_tab == 'waitlist') {
        return;
      } else if (_tab == 'registrations') {
        _loadRegistrations(more: true);
      } else {
        _loadOrders(more: true);
      }
    }
  }

  Future<void> _loadRegistrations({bool more = false}) async {
    if (more && (_regs.nextCursor == null || _regs.loadingMore)) return;
    setState(() {
      if (more) {
        _regs.loadingMore = true;
      } else {
        _regs.loading = _regs.items.isEmpty;
        _regs.error = null;
        _regs.cachedAt = null;
      }
    });
    try {
      final results = await Future.wait([
        _api.listEventRegistrations(
          cursor: more ? _regs.nextCursor : null,
          limit: MemberEventOrdersPage.pageSize,
        ),
        if (!more) _claimableSafe(),
      ]);
      if (!mounted) return;
      final page = results[0];
      final items = [
        for (final r in page['items'] is List ? page['items'] as List : [])
          if (r is Map) EventRegistration.fromJson(r),
      ];
      setState(() {
        if (more) {
          _regs.items.addAll(items);
          _regs.loadingMore = false;
        } else {
          _regs.items = items;
          _regs.loading = false;
          _claimable = results.length > 1
              ? [
                  for (final c
                      in (results[1]['items'] is List
                          ? results[1]['items'] as List
                          : []))
                    if (c is Map) ClaimPreview.fromJson(c),
                ]
              : _claimable;
        }
        _regs.nextCursor = page['nextCursor']?.toString();
      });
      if (!more) EventsCache.putMine('registrations', page);
    } catch (e) {
      if (!mounted) return;
      if (!more && isNetworkError(e)) {
        final cached = await EventsCache.getMine('registrations');
        if (!mounted) return;
        if (cached != null) {
          setState(() {
            _regs.items = [
              for (final r
                  in cached.$2['items'] is List
                      ? cached.$2['items'] as List
                      : [])
                if (r is Map) EventRegistration.fromJson(r),
            ];
            _regs.cachedAt = cached.$1;
            _regs.loading = false;
            _regs.nextCursor = null;
          });
          return;
        }
      }
      setState(() {
        _regs.loading = false;
        _regs.loadingMore = false;
        _regs.error = e;
      });
    }
  }

  /// `claimable` never blocks the list: a failure just hides the cards.
  Future<Map<String, dynamic>> _claimableSafe() async {
    try {
      return await _api.claimableEventRegistrations();
    } catch (_) {
      return const {'items': []};
    }
  }

  Future<void> _loadOrders({bool more = false}) async {
    if (more && (_orders.nextCursor == null || _orders.loadingMore)) return;
    setState(() {
      if (more) {
        _orders.loadingMore = true;
      } else {
        _orders.loading = _orders.items.isEmpty;
        _orders.error = null;
        _orders.cachedAt = null;
      }
    });
    try {
      final page = await _api.listEventOrders(
        cursor: more ? _orders.nextCursor : null,
        limit: MemberEventOrdersPage.pageSize,
      );
      if (!mounted) return;
      final items = [
        for (final o in page['items'] is List ? page['items'] as List : [])
          if (o is Map) EventOrder.fromJson(o),
      ];
      setState(() {
        if (more) {
          _orders.items.addAll(items);
          _orders.loadingMore = false;
        } else {
          _orders.items = items;
          _orders.loading = false;
        }
        _orders.nextCursor = page['nextCursor']?.toString();
      });
      if (!more) EventsCache.putMine('orders', page);
    } catch (e) {
      if (!mounted) return;
      if (!more && isNetworkError(e)) {
        final cached = await EventsCache.getMine('orders');
        if (!mounted) return;
        if (cached != null) {
          setState(() {
            _orders.items = [
              for (final o
                  in cached.$2['items'] is List
                      ? cached.$2['items'] as List
                      : [])
                if (o is Map) EventOrder.fromJson(o),
            ];
            _orders.cachedAt = cached.$1;
            _orders.loading = false;
            _orders.nextCursor = null;
          });
          return;
        }
      }
      setState(() {
        _orders.loading = false;
        _orders.loadingMore = false;
        _orders.error = e;
      });
    }
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.memberActivity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.mine.title')),
      ),
      body: !_started
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => _tab == 'waitlist' && _waitlistCtl != null
                  ? _waitlistCtl!.load()
                  : _tab == 'tickets'
                  ? _tickets.load()
                  : _tab == 'registrations'
                  ? _loadRegistrations()
                  : _loadOrders(),
              child: ListView(
                key: const Key('mine-scroll'),
                controller: _scroll,
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                children: [
                  FFSegmented(
                    key: const Key('mine-tabs'),
                    value: _tab,
                    options: [
                      if (_qr) ('tickets', context.tr('events.tickets.title')),
                      (
                        'registrations',
                        context.tr('events.mine.registrations'),
                      ),
                      ('orders', context.tr('events.mine.orders')),
                      if (_waitlist)
                        ('waitlist', context.tr('events.waitlist.list.title')),
                    ],
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (_tab == 'tickets' && _qr)
                    MemberEventTicketsView(
                      controller: _tickets,
                      now: widget.now,
                    )
                  else if (_tab == 'waitlist' && _waitlistCtl != null)
                    MemberEventWaitlistView(
                      controller: _waitlistCtl!,
                      options: widget.options,
                      now: widget.now == null ? null : () => widget.now!,
                    )
                  else if (_tab == 'registrations' || _tab == 'tickets')
                    ..._registrationsTab(context)
                  else
                    ..._ordersTab(context),
                ],
              ),
            ),
    );
  }

  List<Widget> _registrationsTab(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final cards = _claimable.where(
      (c) => !_dismissed.contains(c.registrationId),
    );
    return [
      if (_regs.cachedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('mine-offline'),
            tone: FFAlertTone.warning,
            message: context
                .tr('events.offline.savedCopy')
                .replaceFirst(
                  '{time}',
                  formatDateTime(_regs.cachedAt, locale: lang),
                ),
          ),
        ),
      if (cards.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.claim.isThisYou')),
        for (final c in cards) _claimCard(context, c),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      if (_regs.loading)
        FFSkeletonList(
          key: const Key('mine-regs-loading'),
          semanticLabel: context.tr('common.loading'),
        )
      else if (_regs.error != null && _regs.items.isEmpty)
        FFErrorState(
          key: const Key('mine-regs-error'),
          message: errorMessage(FFLocaleScope.of(context), _regs.error!),
          retryLabel: context.tr('common.retry'),
          onRetry: _loadRegistrations,
        )
      else if (_regs.items.isEmpty)
        FFEmptyState(
          key: const Key('mine-regs-empty'),
          icon: Icons.confirmation_number_outlined,
          title: context.tr('events.mine.empty.title'),
          body: context.tr('events.mine.empty.body'),
          action: FFButton(
            key: const Key('mine-browse'),
            label: context.tr('events.mine.empty.action'),
            variant: FFButtonVariant.secondary,
            onPressed: () => context.go(AppRoutes.memberEvents),
          ),
        )
      else ...[
        for (final r in _regs.items) _registrationCard(context, r),
        if (_regs.loadingMore)
          const Padding(
            padding: EdgeInsets.all(FFTokens.spacingMd),
            child: Center(child: FFSpinner()),
          ),
      ],
    ];
  }

  Widget _claimCard(BuildContext context, ClaimPreview c) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final type = context.tr('events.claim.type.${c.contactType}');
    return FFCard(
      key: Key('claim-card-${c.registrationId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context
                .tr('events.claim.card')
                .replaceFirst('{purchaser}', c.purchaserMasked)
                .replaceFirst('{name}', c.participantMasked)
                .replaceFirst('{event}', c.event?.title ?? '')
                .replaceFirst('{category}', c.categoryName),
            style: tt.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context
                .tr('events.claim.matches')
                .replaceFirst('{type}', type)
                .replaceFirst('{masked}', c.contactMasked),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            children: [
              FFButton(
                key: Key('claim-yes-${c.registrationId}'),
                label: context.tr('events.claim.yes'),
                size: FFButtonSize.sm,
                onPressed: () => context.push(
                  AppRoutes.memberEventClaimPath(c.registrationId ?? ''),
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              FFButton(
                key: Key('claim-no-${c.registrationId}'),
                label: context.tr('events.claim.no'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                onPressed: () => _dismiss(c.registrationId ?? ''),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _registrationCard(BuildContext context, EventRegistration r) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final e = r.event;
    final date = e?.startsAt == null
        ? ''
        : eventDayDate(e!.startsAt!, e.utcOffsetMinutes, locale: lang);
    final statusKey = eventRegistrationStatusKey(r.status, r.orderStatus);
    final status = context.tr(statusKey);
    final tone = registrationIsLive(r.status, r.orderStatus)
        ? (r.status == EventRegistrationStatus.confirmed
              ? FFBadgeTone.success
              : FFBadgeTone.warning)
        : FFBadgeTone.gray;
    final who = switch (r.relation) {
      'self' => context.tr('events.participant.you'),
      'claimed' =>
        context
            .tr('events.mine.by')
            .replaceFirst('{name}', r.purchaserNameMasked ?? ''),
      _ => context.tr('events.mine.byYou'),
    };
    return Semantics(
      button: true,
      label: [e?.title ?? '', r.categoryName, r.fullName, status].join(', '),
      child: FFCard(
        key: Key('reg-card-${r.id}'),
        child: InkWell(
          onTap: () =>
              context.push(AppRoutes.memberEventRegistrationPath(r.id)),
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e?.title ?? '',
                        style: tt.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (r.categoryName.isNotEmpty)
                      FFPill(label: r.categoryName),
                  ],
                ),
                if (date.isNotEmpty)
                  Text(
                    date,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(height: FFTokens.spacingXs),
                Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (r.relation == 'self')
                      FFBadge(label: who, tone: FFBadgeTone.brand)
                    else
                      Text(
                        [
                          r.fullName,
                          who,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: tt.bodySmall,
                      ),
                    FFBadge(label: status, tone: tone),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  [
                    if (r.orderReference.isNotEmpty) r.orderReference,
                    if (r.teamName != null) r.teamName!,
                  ].join(' · '),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _ordersTab(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return [
      if (_orders.cachedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('mine-orders-offline'),
            tone: FFAlertTone.warning,
            message: context
                .tr('events.offline.savedCopy')
                .replaceFirst(
                  '{time}',
                  formatDateTime(_orders.cachedAt, locale: lang),
                ),
          ),
        ),
      if (_orders.loading)
        FFSkeletonList(
          key: const Key('mine-orders-loading'),
          semanticLabel: context.tr('common.loading'),
        )
      else if (_orders.error != null && _orders.items.isEmpty)
        FFErrorState(
          key: const Key('mine-orders-error'),
          message: errorMessage(FFLocaleScope.of(context), _orders.error!),
          retryLabel: context.tr('common.retry'),
          onRetry: _loadOrders,
        )
      else if (_orders.items.isEmpty)
        FFEmptyState(
          key: const Key('mine-orders-empty'),
          icon: Icons.receipt_long_outlined,
          title: context.tr('events.mine.orders.empty'),
          body: context.tr('events.mine.empty.body'),
        )
      else ...[
        for (final o in _orders.items) _orderCard(context, o),
        if (_orders.loadingMore)
          const Padding(
            padding: EdgeInsets.all(FFTokens.spacingMd),
            child: Center(child: FFSpinner()),
          ),
      ],
    ];
  }

  Widget _orderCard(BuildContext context, EventOrder o) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = context.tr(eventOrderStatusKey(o.status));
    final tone = eventOrderStatusTone(o.status);
    final places = context
        .tr('events.order.places')
        .replaceFirst('{n}', '${o.placesCount}');
    final total = o.totalTzs == 0
        ? context.tr('events.card.free')
        : formatCurrency(o.totalTzs, currency: o.currency);
    return Semantics(
      button: true,
      label: [
        o.reference,
        o.event?.title ?? '',
        places,
        total,
        status,
      ].join(', '),
      child: FFCard(
        key: Key('order-card-${o.id}'),
        child: InkWell(
          onTap: () => context.push(AppRoutes.memberEventOrder(o.id)),
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.reference,
                        style: tt.titleSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    FFBadge(label: status, tone: tone),
                  ],
                ),
                Text(o.event?.title ?? '', style: tt.bodyMedium),
                Text(
                  '$places · $total',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (o.isAwaitingPayment && o.holdExpiresAt != null)
                  FFCountdownText(
                    until: o.holdExpiresAt!,
                    now: widget.now == null ? null : () => widget.now!,
                    minutesLabel: context.tr('events.order.left'),
                    secondsLabel: context.tr('events.order.leftSeconds'),
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    urgentStyle: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: fuelTextColor(context),
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

class _PagedList<T> {
  List<T> items = [];
  String? nextCursor;
  bool loading = true;
  bool loadingMore = false;
  Object? error;
  DateTime? cachedAt;
}
