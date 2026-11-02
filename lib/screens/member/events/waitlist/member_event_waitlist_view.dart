import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/events/waitlist.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../event_status.dart';
import '../events_registration_gate.dart';

/// East-African and nearby zones that never change their offset, so a list
/// row (which carries the IANA name only) can still be shown on the event's
/// own clock. Anything else falls back to the row's own
/// `utcOffsetMinutes` / `timezoneAbbr` when the server sends them.
const Map<String, (int, String)> _fixedZones = {
  'Africa/Dar_es_Salaam': (180, 'EAT'),
  'Africa/Nairobi': (180, 'EAT'),
  'Africa/Kampala': (180, 'EAT'),
  'Africa/Addis_Ababa': (180, 'EAT'),
  'Africa/Mogadishu': (180, 'EAT'),
  'Africa/Kigali': (120, 'CAT'),
  'Africa/Lusaka': (120, 'CAT'),
  'Africa/Harare': (120, 'CAT'),
  'Africa/Maputo': (120, 'CAT'),
  'Africa/Lubumbashi': (120, 'CAT'),
  'UTC': (0, 'UTC'),
};

/// The clock an entry's deadline is read on: the server's own offset when it
/// sent one, else the fixed-zone table, else the device's (no abbreviation).
({int offset, String abbr}) waitlistClock(WaitlistEntry e, DateTime at) {
  if (e.utcOffsetMinutes != null) {
    return (offset: e.utcOffsetMinutes!, abbr: e.timezoneAbbr);
  }
  final known = _fixedZones[e.timezone];
  if (known != null) return (offset: known.$1, abbr: known.$2);
  return (offset: deviceOffsetMinutes(at), abbr: '');
}

/// Announces a held ticket's clock politely at one hour, 15 minutes and 5
/// minutes left (spec §11): a live region that changes only then, never per
/// second. The visible countdown is [FFCountdownText].
class OfferCountdown extends StatefulWidget {
  const OfferCountdown({
    super.key,
    required this.until,
    required this.now,
    this.onDone,
  });

  final DateTime until;
  final DateTime Function() now;
  final VoidCallback? onDone;

  @override
  State<OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<OfferCountdown> {
  Timer? _timer;
  int _stage = 0;

  int _stageOf() {
    final m = widget.until.difference(widget.now()).inMinutes;
    if (m <= 5) return 5;
    if (m <= 15) return 15;
    if (m <= 60) return 60;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _stage = _stageOf();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final s = _stageOf();
      if (mounted && s != _stage) setState(() => _stage = s);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final text = FFCountdownText(
      until: widget.until,
      now: widget.now,
      minutesLabel: context.tr('events.order.left'),
      secondsLabel: context.tr('events.order.leftSeconds'),
      style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      urgentStyle: tt.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: fuelTextColor(context),
      ),
      onDone: widget.onDone,
    );
    final left = _stage == 0
        ? ''
        : context.tr('events.order.left').replaceFirst('{n}', '$_stage');
    return Stack(
      children: [
        ExcludeSemantics(child: text),
        Semantics(
          liveRegion: true,
          label: left,
          child: const SizedBox(width: 1, height: 1),
        ),
      ],
    );
  }
}

/// The member's waitlist as a column of cards (spec §4.10): used by the Mine
/// tab and by [MemberEventWaitlistPage]. Owns nothing; the page owns the
/// [WaitlistController].
class MemberEventWaitlistView extends StatelessWidget {
  const MemberEventWaitlistView({
    super.key,
    required this.controller,
    this.options,
    this.now,
  });

  final WaitlistController controller;
  final EventsOptions? options;

  /// Injectable clock (tests); the server's `serverTime` skew is applied on
  /// top of it.
  final DateTime Function()? now;

  DateTime Function() _clock() {
    final base = now ?? DateTime.now;
    final server = controller.page.serverTime;
    if (server == null) return base;
    final skew = server.difference(base());
    return () => base().add(skew);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final lang = FFLocaleScope.of(context).locale.languageCode;
        final c = controller;
        if (c.loading) {
          return FFSkeletonList(
            key: const Key('waitlist-loading'),
            semanticLabel: context.tr('common.loading'),
          );
        }
        if (c.error != null && c.page.items.isEmpty) {
          return FFErrorState(
            key: const Key('waitlist-error'),
            message: errorMessage(FFLocaleScope.of(context), c.error!),
            retryLabel: context.tr('common.retry'),
            onRetry: c.load,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.offline)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFAlert(
                  key: const Key('waitlist-offline'),
                  tone: FFAlertTone.warning,
                  message: context
                      .tr('events.offline.savedCopy')
                      .replaceFirst(
                        '{time}',
                        formatDateTime(c.cachedAt, locale: lang),
                      ),
                ),
              ),
            if (c.page.items.isEmpty)
              FFEmptyState(
                key: const Key('waitlist-empty'),
                icon: Icons.hourglass_empty,
                title: context.tr('events.waitlist.list.empty'),
                action: FFButton(
                  key: const Key('waitlist-browse'),
                  label: context.tr('events.mine.empty.action'),
                  variant: FFButtonVariant.secondary,
                  onPressed: () => context.go(AppRoutes.memberEvents),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final cards = [
                    for (final e in c.page.items)
                      WaitlistCard(
                        entry: e,
                        controller: c,
                        now: _clock(),
                        options: options,
                      ),
                  ];
                  if (box.maxWidth < 840) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cards,
                    );
                  }
                  return Wrap(
                    spacing: FFTokens.spacingSm,
                    runSpacing: FFTokens.spacingSm,
                    children: [
                      for (final card in cards)
                        SizedBox(
                          width: (box.maxWidth - FFTokens.spacingSm) / 2,
                          child: card,
                        ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

IconData _statusIcon(WaitlistStatus s) => switch (s) {
  WaitlistStatus.waiting => Icons.hourglass_top,
  WaitlistStatus.offered => Icons.confirmation_number_outlined,
  WaitlistStatus.converted => Icons.check_circle_outline,
  WaitlistStatus.expired => Icons.timer_off_outlined,
  WaitlistStatus.declined => Icons.undo,
  WaitlistStatus.left => Icons.logout,
  WaitlistStatus.removed => Icons.block,
  _ => Icons.lock_outline,
};

FFBadgeTone _statusTone(WaitlistStatus s) => switch (s) {
  WaitlistStatus.waiting => FFBadgeTone.info,
  WaitlistStatus.offered => FFBadgeTone.fuel,
  WaitlistStatus.converted => FFBadgeTone.success,
  WaitlistStatus.expired || WaitlistStatus.removed => FFBadgeTone.warning,
  _ => FFBadgeTone.gray,
};

/// One waitlist entry: event, ticket, status (text + icon), position or the
/// held ticket's deadline with Pay now, and Leave / Review terms.
class WaitlistCard extends StatefulWidget {
  const WaitlistCard({
    super.key,
    required this.entry,
    required this.controller,
    required this.now,
    this.options,
  });

  final WaitlistEntry entry;
  final WaitlistController controller;
  final DateTime Function() now;
  final EventsOptions? options;

  @override
  State<WaitlistCard> createState() => _WaitlistCardState();
}

class _WaitlistCardState extends State<WaitlistCard> {
  bool _busy = false;

  WaitlistEntry get e => widget.entry;

  Future<void> _leave() async {
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    if (widget.controller.offline) {
      snack.info(context.tr('events.waitlist.offline'));
      return;
    }
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('events.waitlist.leave.title'),
      message: e.status == WaitlistStatus.offered
          ? context.tr('events.waitlist.leave.offeredBody')
          : context.tr('events.waitlist.leave.body'),
      confirmLabel: context.tr('events.waitlist.leave.button'),
      destructive: true,
      confirmKey: Key('waitlist-leave-confirm-${e.id}'),
    );
    if (!ok || !mounted) return;
    final done = context.tr('events.waitlist.leave.done');
    setState(() => _busy = true);
    try {
      await widget.controller.leave(e.id);
      snack.success(done);
    } catch (err) {
      snack.error(
        isNetworkError(err)
            ? locale.t('events.waitlist.offline')
            : waitlistErrorMessage(locale, err),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconfirm() async {
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    if (widget.controller.offline) {
      snack.info(context.tr('events.waitlist.offline'));
      return;
    }
    final version =
        widget.options?.consentTextVersion ??
        eventsOptionsOf(context, null).consentTextVersion;
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('events.waitlist.reconfirm.button'),
      message: context.tr('events.review.accept'),
      confirmLabel: context.tr('common.confirm'),
      confirmKey: Key('waitlist-reconfirm-confirm-${e.id}'),
    );
    if (!ok || !mounted) return;
    final done = context.tr('events.waitlist.reconfirm.done');
    setState(() => _busy = true);
    try {
      await widget.controller.reconfirm(e.id, textVersion: version);
      snack.success(done);
    } catch (err) {
      snack.error(
        isNetworkError(err)
            ? locale.t('events.waitlist.offline')
            : waitlistErrorMessage(locale, err),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pay() {
    final offer = e.offer;
    if (offer == null) return;
    EventsAnalytics.waitlistOfferOpened(eventId: e.eventId);
    context.push(AppRoutes.memberEventOrderPayPath(offer.orderId));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final status = context.tr('events.waitlist.status.${e.status.wire}');
    final offer = e.status == WaitlistStatus.offered ? e.offer : null;
    final expires = offer?.expiresAt;
    final ticket = [
      e.ticketTypeName,
      e.categoryName,
    ].where((s) => s.isNotEmpty).join(' · ');
    final position = e.status == WaitlistStatus.waiting ? e.position : null;
    final endedKey = 'events.waitlist.ended.${e.endedReason ?? ''}';
    final endedText = e.status.live ? endedKey : context.tr(endedKey);
    final showEnded = !e.status.live && endedText != endedKey;
    String? deadline;
    if (expires != null) {
      final z = waitlistClock(e, expires);
      deadline = context
          .tr('events.waitlist.offer.body')
          .replaceFirst(
            '{time}',
            '${eventDayChip(expires, z.offset, locale: lang)}, '
                '${eventTime(expires, z.offset, z.abbr, locale: lang)}',
          );
    }
    return FFCard(
      key: Key('waitlist-card-${e.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(e.eventTitle, style: tt.titleMedium),
          ),
          if (ticket.isNotEmpty)
            Text(
              ticket,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: FFTokens.spacingXs),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(_statusIcon(e.status), size: 18, color: cs.onSurface),
              FFBadge(
                key: Key('waitlist-status-${e.id}'),
                label: status,
                tone: _statusTone(e.status),
                wrap: true,
              ),
              if (position != null)
                Semantics(
                  label: context
                      .tr('events.waitlist.sem.position')
                      .replaceFirst('{n}', '$position'),
                  child: ExcludeSemantics(
                    child: Text(
                      context
                          .tr('events.waitlist.joined.position')
                          .replaceFirst('{n}', '$position'),
                      key: Key('waitlist-position-${e.id}'),
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (offer != null && expires != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('events.waitlist.offer.title'),
              style: tt.titleSmall,
            ),
            Text(
              deadline!,
              key: Key('waitlist-deadline-${e.id}'),
              style: tt.bodyMedium,
            ),
            OfferCountdown(until: expires, now: widget.now),
            const SizedBox(height: FFTokens.spacingSm),
            FFButton(
              key: Key('waitlist-pay-${e.id}'),
              label: context.tr('events.waitlist.offer.pay'),
              fullWidth: true,
              onPressed: _busy ? null : _pay,
            ),
          ],
          if (e.needsReconsent) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFAlert(
              key: Key('waitlist-reconsent-${e.id}'),
              tone: FFAlertTone.warning,
              message: context.tr('events.waitlist.reconfirm.banner'),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            FFButton(
              key: Key('waitlist-reconfirm-${e.id}'),
              label: context.tr('events.waitlist.reconfirm.button'),
              variant: FFButtonVariant.secondary,
              loading: _busy,
              onPressed: _busy ? null : _reconfirm,
            ),
          ],
          if (showEnded) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              endedText,
              key: Key('waitlist-ended-${e.id}'),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (e.status.live) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('waitlist-leave-${e.id}'),
                label: context.tr('events.waitlist.leave.button'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                onPressed: _busy ? null : _leave,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `/member/events/waitlist` (spec §4.10): the same list as a page.
class MemberEventWaitlistPage extends StatefulWidget {
  const MemberEventWaitlistPage({super.key, this.options, this.now});

  final EventsOptions? options;
  final DateTime Function()? now;

  @override
  State<MemberEventWaitlistPage> createState() =>
      _MemberEventWaitlistPageState();
}

class _MemberEventWaitlistPageState extends State<MemberEventWaitlistPage> {
  WaitlistController? _ctl;
  bool _allowed = false;

  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!eventsRegistrationAllowed(context, _options)) return;
      final ctl = WaitlistController(api: AppScope.of(context).api);
      setState(() {
        _ctl = ctl;
        _allowed = true;
      });
      ctl.load();
    });
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.memberEvents);

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.waitlist.list.title')),
      ),
      body: !_allowed || ctl == null
          ? const SizedBox.shrink()
          : !_options.waitlist.enabled
          ? Center(
              child: FFEmptyState(
                key: const Key('waitlist-unavailable'),
                icon: Icons.hourglass_empty,
                title: context.tr('events.waitlist.error.unavailable'),
              ),
            )
          : RefreshIndicator(
              onRefresh: ctl.load,
              child: ListView(
                key: const Key('waitlist-scroll'),
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                children: [
                  MemberEventWaitlistView(
                    controller: ctl,
                    options: widget.options,
                    now: widget.now,
                  ),
                ],
              ),
            ),
    );
  }
}
