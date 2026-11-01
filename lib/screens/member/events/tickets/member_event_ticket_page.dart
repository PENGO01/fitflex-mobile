import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_ticket.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../events_registration_gate.dart';
import '../results/event_result_entry.dart';

/// Two columns from here (Flutter web desktop; spec §9.1).
const double _wideAt = 840;

enum _Phase { loading, ready, revoked, claimedElsewhere, rotateRequired, error }

/// `/member/events/registrations/:registrationId/ticket` (events S4 spec
/// §5.5, §5.8). Draws the QR from the server's own payload; the ticket
/// number, participant, category and state are text too, so a screen-reader
/// user never depends on the picture. Makes no claim that the code gets
/// anyone anywhere: while kit scanning is not live it says so.
class MemberEventTicketPage extends StatefulWidget {
  const MemberEventTicketPage({
    super.key,
    required this.registrationId,
    this.options,
  });

  final String registrationId;
  final EventsOptions? options;

  @override
  State<MemberEventTicketPage> createState() => _MemberEventTicketPageState();
}

class _MemberEventTicketPageState extends State<MemberEventTicketPage>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.loading;
  EventTicketPayload? _ticket;
  DateTime? _savedAt;
  bool _offline = false;
  bool _busy = false;
  Object? _error;
  String _revokedReason = 'cancelled';
  String _claimedName = '';
  final _heading = FocusNode(debugLabel: 'ticket-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heading.dispose();
    super.dispose();
  }

  /// Back from the background: the kit may have been collected meanwhile
  /// (spec §9.1), so read the ticket again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        _phase == _Phase.ready &&
        !_busy) {
      _load();
    }
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  void _focusHeading() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _heading.requestFocus();
  });

  Future<void> _load() async {
    setState(() {
      _phase = _ticket == null ? _Phase.loading : _phase;
      _error = null;
    });
    final id = widget.registrationId;
    try {
      final json = await _api.getEventTicket(id);
      if (!mounted) return;
      final t = EventTicketPayload.fromJson(json);
      await EventTicketCache.put(id, json, eventStartsAt: t.event?.startsAt);
      if (!mounted) return;
      EventsAnalytics.ticketOpened(registrationId: id);
      setState(() {
        _ticket = t;
        _savedAt = null;
        _offline = false;
        _phase = _Phase.ready;
      });
      _focusHeading();
    } on ApiException catch (e) {
      if (!mounted) return;
      await _onRefused(e);
    } catch (e) {
      if (!mounted) return;
      await _onUnreachable(e);
    }
  }

  Future<void> _onRefused(ApiException e) async {
    final id = widget.registrationId;
    final cached = await EventTicketCache.get(id);
    switch (e.code) {
      case 'ticket_revoked':
        final reason = e.body is Map
            ? (e.body as Map)['reason']?.toString()
            : null;
        await EventTicketCache.remove(id);
        if (!mounted) return;
        setState(() {
          _revokedReason =
              const {
                'cancelled',
                'event_cancelled',
                'refunded',
              }.contains(reason)
              ? reason!
              : 'cancelled';
          _ticket = null;
          _phase = _Phase.revoked;
        });
        _focusHeading();
      case 'rotate_required':
        // The signing key was retired: the old code can't be shown, a new
        // one can be made.
        await EventTicketCache.remove(id);
        if (!mounted) return;
        setState(() {
          _ticket = null;
          _phase = _Phase.rotateRequired;
        });
        _focusHeading();
      case 'ticket_not_issued':
        // Paid but not issued yet: the registration page says what is going
        // on ("being prepared").
        if (!mounted) return;
        context.pushReplacement(AppRoutes.memberEventRegistrationPath(id));
      case 'registration_not_found':
        await EventTicketCache.remove(id);
        if (!mounted) return;
        setState(() {
          _claimedName = cached?.ticket.firstName ?? _claimedName;
          _ticket = null;
          _phase = _Phase.claimedElsewhere;
        });
        _focusHeading();
      default:
        setState(() {
          _error = e;
          _phase = _ticket == null ? _Phase.error : _phase;
        });
    }
  }

  Future<void> _onUnreachable(Object e) async {
    final cached = await EventTicketCache.get(widget.registrationId);
    if (!mounted) return;
    if (isNetworkError(e) && cached != null) {
      setState(() {
        _ticket = cached.ticket;
        _savedAt = cached.savedAt;
        _offline = true;
        _phase = _Phase.ready;
      });
      _focusHeading();
      return;
    }
    setState(() {
      _error = e;
      _phase = _ticket == null ? _Phase.error : _phase;
    });
  }

  Future<void> _rotate() async {
    if (_busy) return;
    final yes = await showFFConfirmDialog(
      context,
      title: context.tr('events.ticket.rotate.title'),
      message: context.tr('events.ticket.rotate.body'),
      confirmLabel: context.tr('events.ticket.rotate'),
      cancelLabel: context.tr('common.cancel'),
      confirmKey: const Key('ticket-rotate-confirm'),
      cancelKey: const Key('ticket-rotate-cancel'),
    );
    if (!yes || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('events.ticket.rotate.done');
    setState(() => _busy = true);
    try {
      final json = await _api.rotateEventTicket(widget.registrationId);
      if (!mounted) return;
      final t = EventTicketPayload.fromJson(json);
      // The old code is dropped from this phone with the old payload.
      await EventTicketCache.put(
        widget.registrationId,
        json,
        eventStartsAt: t.event?.startsAt,
      );
      if (!mounted) return;
      EventsAnalytics.ticketRotated();
      setState(() {
        _ticket = t;
        _savedAt = null;
        _busy = false;
      });
      snack.success(done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'ticket_revoked') {
        await _onRefused(e);
      } else {
        snack.error(eventsErrorMessage(locale, e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(eventsErrorMessage(locale, e));
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(
          AppRoutes.memberEventRegistrationPath(widget.registrationId),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.reg.ticket')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('ticket-loading'),
          semanticLabel: context.tr('events.ticket.loading'),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('ticket-error'),
            message: _error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _ => _content(context),
      },
    );
  }

  Widget _content(BuildContext context) {
    final children = switch (_phase) {
      _Phase.revoked => _revoked(context),
      _Phase.claimedElsewhere => _claimed(context),
      _Phase.rotateRequired => _rotateRequired(context),
      _ => _ready(context, _ticket!),
    };
    return ListView(
      key: const Key('ticket-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  _phase == _Phase.ready &&
                      MediaQuery.sizeOf(context).width >= _wideAt
                  ? 960
                  : 640,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _revoked(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: Text(
            context.tr('events.ticket.revoked.$_revokedReason'),
            key: const Key('ticket-revoked-title'),
            style: tt.titleLarge,
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      // No QR is drawn for a ticket that no longer works.
      FFCard(
        key: const Key('ticket-revoked'),
        child: Row(
          children: [
            const Icon(Icons.block_outlined),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Text(
                context.tr('events.ticket.revoked.body'),
                style: tt.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      _viewRegistration(context),
    ];
  }

  /// Rotate, then read the ticket again.
  Future<void> _rotateThenReload() async {
    if (_busy) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      await _api.rotateEventTicket(widget.registrationId);
      if (!mounted) return;
      EventsAnalytics.ticketRotated();
      setState(() => _busy = false);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'ticket_revoked') {
        await _onRefused(e);
      } else {
        snack.error(eventsErrorMessage(locale, e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(eventsErrorMessage(locale, e));
    }
  }

  List<Widget> _rotateRequired(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: Text(context.tr('events.ticket.show'), style: tt.titleLarge),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFCard(
        key: const Key('ticket-rotate-required'),
        child: Text(
          context.tr('error.reason.rotate_required'),
          style: tt.bodyMedium,
        ),
      ),
      FFButton(
        key: const Key('ticket-rotate-now'),
        label: context.tr('events.ticket.rotate'),
        loading: _busy,
        onPressed: _rotateThenReload,
      ),
      _viewRegistration(context),
    ];
  }

  List<Widget> _claimed(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final name = _claimedName.trim();
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: Text(context.tr('events.ticket.show'), style: tt.titleLarge),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFCard(
        key: const Key('ticket-claimed-elsewhere'),
        child: Text(
          name.isEmpty
              ? context.tr('events.ticket.claimedElsewhere.generic')
              : context
                    .tr('events.ticket.claimedElsewhere')
                    .replaceFirst('{name}', name),
          style: tt.bodyMedium,
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FFButton(
          key: const Key('ticket-claimed-back'),
          label: context.tr('events.mine.title'),
          variant: FFButtonVariant.ghost,
          onPressed: () => context.go(AppRoutes.memberEventTickets),
        ),
      ),
    ];
  }

  Widget _viewRegistration(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FFButton(
      key: const Key('ticket-view-registration'),
      label: context.tr('events.ticket.view'),
      variant: FFButtonVariant.ghost,
      onPressed: () => context.push(
        AppRoutes.memberEventRegistrationPath(widget.registrationId),
      ),
    ),
  );

  Future<void> _directions(KitCollectionPoint p) async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${p.lat},${p.lng}',
    });
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Bib number and kit status (events S5 spec §9.1). Both come from the
  /// server; with kit operations off it sends neither, and nothing shows.
  List<Widget> _bibAndKit(
    BuildContext context,
    EventTicketPayload t,
    bool scanning,
  ) {
    final kit = t.kit;
    if (!scanning && kit == null && t.bibNumber == null) return const [];
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = t.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final bib = t.bibNumber;
    final out = <Widget>[const SizedBox(height: FFTokens.spacingMd)];
    if (bib != null) {
      out.add(
        Semantics(
          container: true,
          label: context
              .tr('events.ticket.bib.a11y')
              .replaceFirst('{number}', bib),
          child: ExcludeSemantics(
            child: Text(
              context.tr('events.ticket.bib').replaceFirst('{number}', bib),
              key: const Key('ticket-bib'),
              style: tt.headlineMedium,
            ),
          ),
        ),
      );
    } else if (scanning) {
      out.add(
        Text(
          context.tr('events.ticket.bib.none'),
          key: const Key('ticket-bib-none'),
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    if (kit == null) return out;

    final (chipKey, tone) = switch (kit.state) {
      'ready' => ('events.ticket.kit.ready', FFBadgeTone.success),
      'collected' => ('events.ticket.kit.collected', FFBadgeTone.success),
      // An exception is internal to the organizer: the member sees "not
      // ready" and is told to ask.
      _ => ('events.ticket.kit.not_ready', FFBadgeTone.gray),
    };
    final collectedAt = kit.collectedAt;
    final point = kit.collectionPointName;
    out
      ..add(const SizedBox(height: FFTokens.spacingMd))
      ..add(
        Semantics(
          header: true,
          child: Text(
            context.tr('events.ticket.kit.title'),
            style: tt.titleMedium,
          ),
        ),
      )
      ..add(const SizedBox(height: FFTokens.spacingXs))
      ..add(
        Align(
          alignment: Alignment.centerLeft,
          child: FFBadge(
            key: const Key('ticket-kit-state'),
            label: context.tr(chipKey),
            tone: tone,
            wrap: true,
          ),
        ),
      );
    if (kit.isException) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            context.tr('events.ticket.kit.exception'),
            key: const Key('ticket-kit-exception'),
            style: tt.bodyMedium,
          ),
        ),
      );
    }
    if (kit.isCollected) {
      final date = collectedAt == null
          ? ''
          : eventDateTime(collectedAt, off, abbr, locale: lang);
      final line = date.isEmpty
          ? ''
          : (point == null || point.isEmpty)
          ? context
                .tr('events.ticket.kit.collectedOn')
                .replaceFirst('{date}', date)
          : context
                .tr('events.ticket.kit.collectedAt')
                .replaceFirst('{date}', date)
                .replaceFirst('{point}', point);
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (line.isNotEmpty)
                Text(
                  line,
                  key: const Key('ticket-kit-collected'),
                  style: tt.bodyMedium,
                ),
              Text(
                context.tr('events.ticket.kit.noNeed'),
                key: const Key('ticket-kit-noneed'),
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    if (kit.isReady) {
      final now = DateTime.now();
      for (final p in t.collectionPoints) {
        final w = p.nextWindow(now);
        final how = p.instructions.of(lang).trim();
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFCard(
              key: Key('ticket-kit-point-${p.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('events.ticket.kit.where'),
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(p.name, style: tt.titleSmall),
                  if (p.address.isNotEmpty)
                    Text(p.address, style: tt.bodyMedium),
                  if (w != null) ...[
                    const SizedBox(height: FFTokens.spacingXs),
                    Text(
                      context.tr('events.ticket.kit.when'),
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      eventWindowText(
                        w.opensAt,
                        w.closesAt,
                        off,
                        abbr,
                        locale: lang,
                      ),
                      key: Key('ticket-kit-window-${p.id}'),
                      style: tt.bodyMedium,
                    ),
                  ],
                  if (how.isNotEmpty) ...[
                    const SizedBox(height: FFTokens.spacingXs),
                    Text(how, style: tt.bodyMedium),
                  ],
                  if (p.hasLocation)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FFButton(
                        key: Key('ticket-kit-directions-${p.id}'),
                        label: context.tr('events.ticket.kit.directions'),
                        variant: FFButtonVariant.ghost,
                        onPressed: () => _directions(p),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    }
    if (_offline) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: Text(
            context.tr('events.ticket.kit.staleHint'),
            key: const Key('ticket-kit-stale'),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _ready(BuildContext context, EventTicketPayload t) {
    final tt = Theme.of(context).textTheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = t.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final scanning = t.scanning || _options.tickets.scanning;
    final when = e?.startsAt == null
        ? null
        : eventDateTime(e!.startsAt!, off, abbr, locale: lang);
    final label = context
        .tr('events.ticket.qr.a11y')
        .replaceFirst('{name}', t.participantName)
        .replaceFirst('{category}', t.categoryName)
        .replaceFirst('{code}', t.displayCode);
    final wide = MediaQuery.sizeOf(context).width >= _wideAt;
    final top = <Widget>[
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: FFPageHeader(
            title: e?.title ?? context.tr('events.ticket.show'),
            description: when,
          ),
        ),
      ),
      if (_offline)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('ticket-offline'),
            tone: FFAlertTone.warning,
            message: context.tr('events.ticket.offline'),
          ),
        ),
    ];
    final qrPart = <Widget>[
      // The code: fixed dark ink on white in both themes, with a quiet zone.
      FFCard(
        padding: EdgeInsets.zero,
        child: Container(
          key: const Key('ticket-qr-card'),
          color: FFTokens.qrBackground,
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, c) {
              final size = (c.maxWidth).clamp(240.0, 320.0);
              return Center(
                child: Semantics(
                  container: true,
                  label: label,
                  image: true,
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: size,
                      child: FFQrCode(
                        key: const Key('ticket-qr'),
                        data: t.drawn,
                        size: size,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      Text(
        t.participantName,
        key: const Key('ticket-participant'),
        style: tt.titleMedium,
      ),
      Text(
        [
          t.categoryName,
          t.ticketTypeName,
        ].where((s) => s.isNotEmpty).join(' · '),
        key: const Key('ticket-category'),
        style: tt.bodyMedium,
      ),
      const SizedBox(height: FFTokens.spacingXs),
      Row(
        children: [
          Expanded(
            child: Text(
              context
                  .tr('events.ticket.number')
                  .replaceFirst('{code}', t.displayCode),
              key: const Key('ticket-number'),
              style: tt.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            key: const Key('ticket-copy-number'),
            tooltip: context.tr('events.ticket.copy'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () async {
              final snack = FFSnack.of(context);
              final copied = context.tr('events.ticket.copied');
              await Clipboard.setData(ClipboardData(text: t.displayCode));
              snack.success(copied);
            },
          ),
        ],
      ),
      Wrap(
        spacing: FFTokens.spacingSm,
        runSpacing: FFTokens.spacingXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FFBadge(
            key: const Key('ticket-state'),
            label: context.tr('events.ticket.ready'),
            tone: FFBadgeTone.success,
          ),
          if (_savedAt != null)
            FFBadge(
              key: const Key('ticket-cached'),
              label: context
                  .tr('events.ticket.cached')
                  .replaceFirst(
                    '{time}',
                    formatDateTime(_savedAt, locale: lang),
                  ),
              tone: FFBadgeTone.gray,
              wrap: true,
            ),
        ],
      ),
    ];
    final restPart = <Widget>[
      const SizedBox(height: FFTokens.spacingSm),
      FFAlert(
        key: const Key('ticket-scan-note'),
        tone: FFAlertTone.info,
        message: context.tr(
          scanning ? 'events.ticket.scan.live' : 'events.ticket.scan.soon',
        ),
      ),
      ..._bibAndKit(context, t, scanning),
      if (t.isHandover) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFAlert(
          key: const Key('ticket-handover'),
          tone: FFAlertTone.info,
          message: context
              .tr('events.ticket.handover')
              .replaceFirst('{name}', t.firstName),
        ),
      ],
      // Events S6: your result and your run (draws nothing while off).
      EventResultEntry(
        registrationId: widget.registrationId,
        event: t.event,
        options: _options,
        confirmed: t.isActive,
        isParticipant: t.relation != 'purchased',
      ),
      const SizedBox(height: FFTokens.spacingMd),
      FFButton(
        key: const Key('ticket-rotate'),
        label: context.tr('events.ticket.rotate'),
        variant: FFButtonVariant.ghost,
        loading: _busy,
        onPressed: _offline ? null : _rotate,
      ),
      _viewRegistration(context),
    ];
    if (!wide) return [...top, ...qrPart, ...restPart];
    return [
      ...top,
      Row(
        key: const Key('ticket-columns'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: qrPart,
            ),
          ),
          const SizedBox(width: FFTokens.spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: restPart,
            ),
          ),
        ],
      ),
    ];
  }
}
