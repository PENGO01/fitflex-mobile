import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_detail.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_analytics.dart';
import '../../../shared/events/events_cache.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/photo_hero_flag.dart';
import '../member_shell.dart';
import 'event_card.dart';
import 'event_status.dart';

/// The bundled photo behind an event with no cover (events S2 spec §11.1
/// asks for a dedicated `events` slot; until the owner picks a licensed
/// photo for it, the Activity "today" scene stands in, §17.5).
const FFHeroPhoto kEventsHeroFallback = FFHeroPhoto.activityToday;

/// `/member/events/:eventId` (events S2 spec §11.4): hero, key facts, the
/// sections in EVT-004 order and the sticky Register bar (disabled in S2;
/// every §11.6 state is here behind the server's `registration` option).
class MemberEventDetailPage extends StatefulWidget {
  const MemberEventDetailPage({
    super.key,
    required this.eventId,
    this.options,
    this.now,
  });

  final String eventId;

  /// The server's options; read from [MemberDataScope] when absent.
  final EventsOptions? options;

  /// Injectable clock ("days left").
  final DateTime? now;

  @override
  State<MemberEventDetailPage> createState() => _MemberEventDetailPageState();
}

class _MemberEventDetailPageState extends State<MemberEventDetailPage> {
  EventDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _gone = false;
  bool _unavailable = false;
  DateTime? _cachedAt;
  bool? _saved;
  bool _aboutExpanded = false;
  bool _termsExpanded = false;
  bool _refundExpanded = false;
  final _heading = FocusNode(debugLabel: 'event-heading');

  ApiClient get _api => AppScope.of(context).api;

  EventsOptions get _options =>
      widget.options ??
      context
          .dependOnInheritedWidgetOfExactType<MemberDataScope>()
          ?.notifier
          ?.eventsOptions ??
      EventsOptions.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _gone = false;
      _unavailable = false;
      _cachedAt = null;
    });
    try {
      final json = await _api.getEvent(widget.eventId);
      if (!mounted) return;
      final detail = EventDetail.fromJson(json);
      setState(() {
        _detail = detail;
        _saved = detail.summary.isSaved;
        _loading = false;
      });
      EventsCache.putDetail(widget.eventId, json);
      EventsAnalytics.detailViewed(
        eventId: detail.id,
        availability: detail.availability.wire,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heading.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 404) {
        setState(() {
          _loading = false;
          if (e.code == 'feature_disabled') {
            _unavailable = true;
          } else {
            _gone = true;
          }
        });
        return;
      }
      if (isNetworkError(e)) {
        final cached = await EventsCache.getDetail(widget.eventId);
        if (!mounted) return;
        if (cached != null) {
          setState(() {
            _detail = EventDetail.fromJson(cached.$2);
            _cachedAt = cached.$1;
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  // ── actions ─────────────────────────────────────────────────────────────

  Future<void> _toggleSave() async {
    final d = _detail;
    if (d == null) return;
    final next = !(_saved ?? false);
    setState(() => _saved = next);
    EventsAnalytics.saved(eventId: d.id, saved: next);
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    try {
      if (next) {
        await _api.saveEvent(d.id);
      } else {
        await _api.unsaveEvent(d.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saved = !next);
      snack.error(errorMessage(locale, e));
    }
  }

  Future<void> _share() async {
    final d = _detail;
    final url = d?.shareUrl;
    if (d == null || url == null) return;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final date = d.summary.startsAt == null
        ? ''
        : eventDayDate(
            d.summary.startsAt!,
            d.summary.utcOffsetMinutes,
            locale: lang,
          );
    final text = context
        .tr('events.share.text')
        .replaceFirst('{title}', d.title)
        .replaceFirst('{date}', date)
        .replaceFirst('{url}', url);
    final snack = FFSnack.of(context);
    final copied = context.tr('common.copied');
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: d.title));
    } catch (_) {
      // No share sheet here (web, a test): the text goes to the clipboard.
      await Clipboard.setData(ClipboardData(text: text));
      snack.success(copied);
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _openMaps(double lat, double lng) => _openExternal(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
  );

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.memberEvents);

  /// Events S3 §5.1: the CTA (or a ticket row) opens the register page.
  void _register(EventDetail d, {String? ticketTypeId}) {
    EventsAnalytics.registrationStarted(
      eventId: d.id,
      source: ticketTypeId == null ? 'cta' : 'ticket_row',
    );
    context.push(AppRoutes.memberEventRegisterPath(d.id, ticket: ticketTypeId));
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.title')),
        actions: [
          if (d != null && options.favourites && !photoHeroUi) ...[
            EventSaveButton(
              key: const Key('event-detail-save'),
              saved: _saved ?? false,
              onPressed: _toggleSave,
            ),
            if (d.shareUrl != null)
              IconButton(
                key: const Key('event-detail-share'),
                tooltip: context.tr('events.share'),
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
              ),
          ],
        ],
      ),
      body: _body(context, options),
      bottomNavigationBar: d == null ? null : _ctaBar(context, d, options),
    );
  }

  Widget _body(BuildContext context, EventsOptions options) {
    if (_unavailable) {
      return Center(
        child: FFEmptyState(
          key: const Key('event-unavailable'),
          icon: Icons.flag_outlined,
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      );
    }
    if (_gone) {
      return Center(
        child: FFEmptyState(
          key: const Key('event-gone'),
          icon: Icons.event_busy_outlined,
          title: context.tr('events.detail.gone.title'),
          body: context.tr('events.detail.gone.body'),
          action: FFButton(
            key: const Key('event-gone-back'),
            label: context.tr('events.detail.back'),
            variant: FFButtonVariant.secondary,
            onPressed: _back,
          ),
        ),
      );
    }
    if (_loading) {
      return ListView(
        key: const Key('event-detail-loading'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Semantics(
            label: context.tr('common.loading'),
            container: true,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: FFSkeleton(height: 200, radius: FFTokens.radiusXl),
                ),
                SizedBox(height: FFTokens.spacingMd),
                FFSkeletonLine(widthFactor: 0.8, height: 20),
                SizedBox(height: FFTokens.spacingSm),
                FFSkeletonLine(widthFactor: 0.5),
                SizedBox(height: FFTokens.spacingLg),
                FFSkeletonLine(),
                SizedBox(height: FFTokens.spacingSm),
                FFSkeletonLine(),
                SizedBox(height: FFTokens.spacingSm),
                FFSkeletonLine(widthFactor: 0.7),
                SizedBox(height: FFTokens.spacingSm),
                FFSkeletonLine(widthFactor: 0.9),
              ],
            ),
          ),
        ],
      );
    }
    final error = _error;
    final d = _detail;
    if (d == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: FFErrorState(
            key: const Key('event-detail-error'),
            message: error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), error),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
      );
    }
    return _content(context, d, options);
  }

  Widget _content(BuildContext context, EventDetail d, EventsOptions options) {
    final locale = FFLocaleScope.of(context);
    final lang = locale.locale.languageCode;
    final s = d.summary;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final off = s.utcOffsetMinutes;
    final abbr = s.timezoneAbbr;
    final eyebrow = [
      if (s.type.isNotEmpty) eventTypeLabel(context, s.type),
      if (s.startsAt != null) eventDayDate(s.startsAt!, off, locale: lang),
    ].join(' · ');
    final subline = [
      s.venue.name,
      s.venue.city,
    ].where((v) => v.trim().isNotEmpty).join(' · ');
    final words = d.title.trim().split(RegExp(r'\s+'));
    final lead = words.length > 1
        ? words.sublist(0, words.length - 1).join(' ')
        : '';
    final accent = words.last;

    final heroActions = <Widget>[
      if (options.favourites) ...[
        EventSaveButton(
          key: const Key('event-detail-save'),
          saved: _saved ?? false,
          onPressed: _toggleSave,
          onPhoto: true,
        ),
        if (d.shareUrl != null)
          FFButton(
            key: const Key('event-detail-share'),
            label: context.tr('common.share'),
            tooltip: context.tr('events.share'),
            variant: FFButtonVariant.onPhoto,
            size: FFButtonSize.sm,
            icon: Icons.share_outlined,
            onPressed: _share,
          ),
      ],
    ];

    final sections = <Widget>[
      if (_cachedAt != null)
        FFAlert(
          key: const Key('event-offline-cached'),
          tone: FFAlertTone.warning,
          message: context
              .tr('events.offline.savedCopy')
              .replaceFirst('{time}', formatDateTime(_cachedAt, locale: lang)),
        ),
      if (s.availability == EventAvailability.cancelled)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('event-cancelled-banner'),
            tone: FFAlertTone.error,
            message: [
              context.tr('events.detail.cancelledBanner'),
              if (d.cancellation?.note.isNotEmpty ?? false)
                d.cancellation!.note.of(lang),
            ].join(' '),
          ),
        ),
      // ── Hero ──────────────────────────────────────────────────────────
      if (photoHeroUi)
        FFHeroBand(
          key: const Key('event-hero'),
          photo: kEventsHeroFallback,
          networkImage: d.heroImageUrl == null
              ? null
              : FFHeroNetworkImage(d.heroImageUrl!),
          headingFocusNode: _heading,
          minHeight: 220,
          wideHeight: 260,
          eyebrow: eyebrow,
          headlineLead: lead.isEmpty ? null : lead,
          headlineAccent: accent,
          subline: subline.isEmpty ? null : subline,
          actions: heroActions,
        )
      else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: d.heroImageUrl == null
                ? EventImagePlaceholder(type: s.type)
                : FFRemoteImage(
                    key: const Key('event-hero-image'),
                    src: d.heroImageUrl!,
                    width: 1200,
                    height: 675,
                    fit: BoxFit.cover,
                    fallback: EventImagePlaceholder(type: s.type),
                  ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (eyebrow.isNotEmpty)
          Text(
            eyebrow.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        Focus(
          focusNode: _heading,
          child: Semantics(
            header: true,
            child: Text(
              d.title,
              key: const Key('event-title'),
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (subline.isNotEmpty)
          Text(
            subline,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
      const SizedBox(height: FFTokens.spacingSm),
      Align(
        alignment: Alignment.centerLeft,
        child: EventAvailabilityPill(event: s),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      // ── Key facts ─────────────────────────────────────────────────────
      _facts(context, d),
      // ── About ─────────────────────────────────────────────────────────
      if (d.description.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.detail.about')),
        if (d.description.missingFor(lang))
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: Text(
              context.tr('events.detail.noSwahili'),
              key: const Key('event-no-swahili'),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        _Expandable(
          key: const Key('event-about'),
          text: d.description.of(lang),
          expanded: _aboutExpanded,
          collapsedLines: 8,
          moreLabel: context.tr('events.detail.readMore'),
          lessLabel: context.tr('events.detail.readLess'),
          onToggle: () => setState(() => _aboutExpanded = !_aboutExpanded),
        ),
      ],
      // ── Results (events S6 §10.1): only once the organizer published and
      // the server has the signed-in board on ─────────────────────────────
      if (options.results.public && d.hasPublishedResults) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFActionTile(
          key: const Key('event-results'),
          icon: Icons.format_list_numbered,
          title: context.tr('events.board.title'),
          subtitle: context.tr(
            d.resultsStage == 'official'
                ? 'events.board.banner.official'
                : 'events.board.banner.provisional',
          ),
          onTap: () => context.push(AppRoutes.memberEventResultsPath(d.id)),
        ),
      ],
      // ── Organizer ─────────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.detail.organizer')),
      Row(
        key: const Key('event-organizer'),
        children: [
          FFAvatar(name: s.organizer.name),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.organizer.name, style: tt.titleSmall),
                if (s.organizer.verified)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: FFBadge(
                      label: context.tr('events.card.verifiedOrganizer'),
                      tone: FFBadgeTone.success,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      // ── Date & time ───────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.detail.dateTime')),
      if (s.startsAt != null)
        _line(
          context,
          context.tr('events.detail.starts'),
          eventDateTime(s.startsAt!, off, abbr, locale: lang),
        ),
      if (s.endsAt != null)
        _line(
          context,
          context.tr('events.detail.ends'),
          eventDateTime(s.endsAt!, off, abbr, locale: lang),
        ),
      Text(
        context
            .tr('events.detail.timezoneNote')
            .replaceFirst('{abbr}', abbr)
            .replaceFirst('{zone}', s.timezone),
        key: const Key('event-timezone-note'),
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      if (s.startsAt != null)
        if (deviceTimeIfDifferent(s.startsAt!, off, locale: lang)
            case final local?)
          Text(
            context.tr('events.detail.localTime').replaceFirst('{time}', local),
            key: const Key('event-local-time'),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      // ── Venue & route ─────────────────────────────────────────────────
      if (s.venue.name.isNotEmpty ||
          (s.venue.address ?? '').isNotEmpty ||
          d.routeUrl != null ||
          d.routeImageUrl != null) ...[
        FFSectionTitle(context.tr('events.detail.venue')),
        if (s.venue.name.isNotEmpty) Text(s.venue.name, style: tt.titleSmall),
        if ((s.venue.address ?? '').isNotEmpty)
          Text(s.venue.address!, style: tt.bodyMedium),
        if (s.venue.cityLine.isNotEmpty)
          Text(
            s.venue.cityLine,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        if (s.venue.hasCoordinates)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('event-open-maps'),
                label: context.tr('events.detail.openMaps'),
                variant: FFButtonVariant.secondary,
                size: FFButtonSize.sm,
                icon: Icons.map_outlined,
                onPressed: () => _openMaps(s.venue.lat!, s.venue.lng!),
              ),
            ),
          ),
        if (d.routeImageUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: Semantics(
              button: true,
              label: d.routeImageAlt ?? context.tr('events.detail.routeImage'),
              child: InkWell(
                key: const Key('event-route-image'),
                onTap: () => _showRouteImage(context, d),
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: FFRemoteImage(
                      src: d.routeImageUrl!,
                      width: 1200,
                      height: 675,
                      fit: BoxFit.cover,
                      fallback: EventImagePlaceholder(type: s.type),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (d.routeUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('event-route-link'),
                label: context.tr('events.detail.routeLink'),
                tooltip: context.tr('events.detail.opensBrowser'),
                semanticLabel:
                    '${context.tr('events.detail.routeLink')}, '
                    '${context.tr('events.detail.opensBrowser')}',
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                trailingIcon: Icons.open_in_new,
                onPressed: () => _openExternal(Uri.parse(d.routeUrl!)),
              ),
            ),
          ),
      ],
      // ── Categories & prices ───────────────────────────────────────────
      FFSectionTitle(context.tr('events.detail.categories')),
      for (final c in d.categories) _category(context, d, c),
      // ── What's included ───────────────────────────────────────────────
      if (d.inclusions.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.detail.inclusions')),
        Text(d.inclusions.of(lang), style: tt.bodyMedium),
      ],
      // ── Eligibility ───────────────────────────────────────────────────
      if (d.categories.any(
        (c) => c.eligibility.isNotEmpty || c.minAge != null,
      )) ...[
        FFSectionTitle(context.tr('events.detail.eligibility')),
        for (final c in d.categories)
          if (c.eligibility.isNotEmpty || c.minAge != null)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: tt.titleSmall),
                  if (c.eligibility.isNotEmpty)
                    Text(c.eligibility.of(lang), style: tt.bodyMedium),
                  if (c.minAge != null)
                    Text(
                      context
                          .tr('events.detail.minAge')
                          .replaceFirst('{n}', '${c.minAge}'),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
      ],
      // ── Accessibility ─────────────────────────────────────────────────
      if (d.accessibility.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.detail.accessibility')),
        Text(d.accessibility.of(lang), style: tt.bodyMedium),
      ],
      // ── Kit collection ────────────────────────────────────────────────
      if (d.collectionPoints.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.detail.kit')),
        for (final p in d.collectionPoints)
          FFCard(
            key: Key('event-kit-${p.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: tt.titleSmall),
                if (p.address.isNotEmpty) Text(p.address, style: tt.bodyMedium),
                for (final w in p.windows)
                  if (w.opensAt != null && w.closesAt != null)
                    Text(
                      eventWindowText(
                        w.opensAt!,
                        w.closesAt!,
                        off,
                        abbr,
                        locale: lang,
                      ),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                if (p.instructions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: Text(p.instructions.of(lang), style: tt.bodySmall),
                  ),
                if (p.hasCoordinates)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                    child: FFButton(
                      label: context.tr('events.detail.openMaps'),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                      icon: Icons.map_outlined,
                      onPressed: () => _openMaps(p.lat!, p.lng!),
                    ),
                  ),
              ],
            ),
          ),
      ],
      // ── Schedule ──────────────────────────────────────────────────────
      if (d.schedule.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.detail.schedule')),
        for (final item in d.schedule)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    item.at == null
                        ? '—'
                        : eventTime(item.at!, off, abbr, locale: lang),
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(item.label.of(lang), style: tt.bodyMedium),
                ),
              ],
            ),
          ),
      ],
      // ── Sponsors ──────────────────────────────────────────────────────
      if (d.sponsors.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.detail.sponsors')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final sp in d.sponsors)
                Padding(
                  padding: const EdgeInsets.only(right: FFTokens.spacingMd),
                  child: sp.logoUrl == null
                      ? FFPill(label: sp.name)
                      : Semantics(
                          label: sp.name,
                          image: true,
                          child: FFRemoteImage(
                            src: sp.logoUrl!,
                            width: 120,
                            height: 60,
                            fit: BoxFit.contain,
                            fallback: FFPill(label: sp.name),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
      // ── Contact ───────────────────────────────────────────────────────
      if (!d.contact.isEmpty) ...[
        FFSectionTitle(context.tr('events.detail.contact')),
        if (d.contact.email case final email?)
          FFActionTile(
            key: const Key('event-contact-email'),
            icon: Icons.mail_outline,
            title: email,
            onTap: () => _openExternal(Uri(scheme: 'mailto', path: email)),
          ),
        if (d.contact.phone case final phone?)
          FFActionTile(
            key: const Key('event-contact-phone'),
            icon: Icons.call_outlined,
            title: phone,
            onTap: () => _openExternal(Uri(scheme: 'tel', path: phone)),
          ),
        if (d.contact.whatsapp case final wa?)
          FFActionTile(
            key: const Key('event-contact-whatsapp'),
            icon: Icons.chat_outlined,
            title: wa,
            subtitle: 'WhatsApp',
            onTap: () => _openExternal(
              Uri.parse(
                'https://wa.me/${wa.replaceAll(RegExp(r'[^0-9]'), '')}',
              ),
            ),
          ),
      ],
      // ── Terms ─────────────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.detail.terms')),
      FFCard(
        child: _Expandable(
          key: const Key('event-terms'),
          text: d.terms.of(lang),
          expanded: _termsExpanded,
          collapsedLines: 3,
          moreLabel: context.tr('events.detail.showAll'),
          lessLabel: context.tr('events.detail.readLess'),
          onToggle: () => setState(() => _termsExpanded = !_termsExpanded),
        ),
      ),
      // ── Refund policy ─────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.detail.refundPolicy')),
      FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (refundPolicyLine(context, d.refundPolicy) case final line?)
              Text(
                line,
                key: const Key('event-refund-summary'),
                style: tt.titleSmall,
              ),
            if (d.refundPolicy.text.isNotEmpty)
              _Expandable(
                key: const Key('event-refund'),
                text: d.refundPolicy.text.of(lang),
                expanded: _refundExpanded,
                collapsedLines: 3,
                moreLabel: context.tr('events.detail.showAll'),
                lessLabel: context.tr('events.detail.readLess'),
                onToggle: () =>
                    setState(() => _refundExpanded = !_refundExpanded),
              ),
          ],
        ),
      ),
      // ── Last updated ──────────────────────────────────────────────────
      const SizedBox(height: FFTokens.spacingMd),
      Row(
        children: [
          Expanded(
            child: Text(
              context
                  .tr('events.detail.updated')
                  .replaceFirst(
                    '{date}',
                    s.updatedAt == null
                        ? '—'
                        : eventDate(s.updatedAt!, off, locale: lang),
                  ),
              key: const Key('event-updated'),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          FFButton(
            key: const Key('event-report'),
            label: context.tr('events.detail.report'),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            onPressed: () => _openExternal(
              Uri(
                scheme: 'mailto',
                path: d.contact.email ?? '',
                queryParameters: {'subject': '${d.title} (${d.id})'},
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingLg),
    ];

    return ListView(
      key: const Key('event-detail-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections,
            ),
          ),
        ),
      ],
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: tt.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Starts · Registration closes · Distances · From price, two per row.
  Widget _facts(BuildContext context, EventDetail d) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final s = d.summary;
    final off = s.utcOffsetMinutes;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final closingSoon = s.availability == EventAvailability.closingSoon;

    Widget fact(String label, Widget value, {Key? key}) => Expanded(
      child: Container(
        key: key,
        padding: const EdgeInsets.all(FFTokens.spacingSm + 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            value,
          ],
        ),
      ),
    );

    Text text(String v, {Color? color}) => Text(
      v,
      style: tt.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final from = s.fromPriceTzs;
    return Column(
      key: const Key('event-facts'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fact(
              context.tr('events.detail.starts'),
              text(
                s.startsAt == null
                    ? '—'
                    : eventDateTime(
                        s.startsAt!,
                        off,
                        s.timezoneAbbr,
                        locale: lang,
                      ),
              ),
              key: const Key('event-fact-starts'),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            fact(
              context.tr('events.detail.regCloses'),
              text(
                s.registrationClosesAt == null
                    ? '—'
                    : eventDateTime(
                        s.registrationClosesAt!,
                        off,
                        s.timezoneAbbr,
                        locale: lang,
                      ),
                color: closingSoon ? fuelTextColor(context) : null,
              ),
              key: const Key('event-fact-closes'),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fact(
              context.tr('events.detail.distances'),
              Wrap(
                spacing: FFTokens.spacingXs,
                runSpacing: FFTokens.spacingXs,
                children: [
                  for (final m in s.distancesM) FFPill(label: distanceLabel(m)),
                  if (s.distancesM.isEmpty) text('—'),
                ],
              ),
              key: const Key('event-fact-distances'),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            fact(
              context.tr('events.detail.fromPrice'),
              text(
                from == null
                    ? '—'
                    : from == 0
                    ? context.tr('events.card.free')
                    : formatCurrency(from, currency: s.currency),
              ),
              key: const Key('event-fact-price'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _category(BuildContext context, EventDetail d, EventCategory c) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final s = d.summary;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return FFCard(
      key: Key('event-category-${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.name, style: tt.titleSmall)),
              if (c.distanceM > 0) FFPill(label: distanceLabel(c.distanceM)),
            ],
          ),
          if (c.startsAt != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                eventDateTime(
                  c.startsAt!,
                  s.utcOffsetMinutes,
                  s.timezoneAbbr,
                  locale: lang,
                ),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (c.remaining != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context
                    .tr('events.detail.left')
                    .replaceFirst('{n}', '${c.remaining}'),
                key: Key('event-category-left-${c.id}'),
                style: tt.bodySmall?.copyWith(
                  color: fuelTextColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final t in c.ticketTypes) _ticket(context, d, t),
        ],
      ),
    );
  }

  Widget _ticket(BuildContext context, EventDetail d, EventTicketType t) {
    final s = d.summary;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final soldOut = t.availability == EventAvailability.soldOut;
    // S3 §5.1: an on-sale row opens the register page with this ticket
    // preselected; sold-out and closed rows stay plain text.
    final tappable =
        _options.registration &&
        (t.availability == EventAvailability.open ||
            t.availability == EventAvailability.closingSoon);
    final muted = cs.onSurfaceVariant;
    final price = t.isFree
        ? context.tr('events.card.free')
        : formatCurrency(t.priceTzs, currency: t.currency);
    final until = t.saleClosesAt == null
        ? null
        : context
              .tr('events.detail.until')
              .replaceFirst(
                '{date}',
                eventDate(t.saleClosesAt!, s.utcOffsetMinutes, locale: lang),
              );
    final line = [t.name, price, ?until].join(' · ');
    final pillEvent = EventSummary(
      id: t.id,
      title: t.name,
      availability: t.availability,
      utcOffsetMinutes: s.utcOffsetMinutes,
      registrationOpensAt: t.saleOpensAt,
    );
    final row = Row(
      children: [
        Expanded(
          child: Text(
            line,
            style: tt.bodyMedium?.copyWith(
              color: soldOut ? muted : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: FFTokens.spacingSm),
        EventAvailabilityPill(event: pillEvent),
        if (tappable) const Icon(Icons.chevron_right, size: 20),
      ],
    );
    if (!tappable) {
      return Padding(
        key: Key('event-ticket-${t.id}'),
        padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
        child: row,
      );
    }
    return Semantics(
      key: Key('event-ticket-${t.id}'),
      button: true,
      label: '${t.name}, $price, ${availabilityLabel(context, pillEvent)}',
      child: InkWell(
        key: Key('event-ticket-tap-${t.id}'),
        onTap: () => _register(d, ticketTypeId: t.id),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
              child: row,
            ),
          ),
        ),
      ),
    );
  }

  /// The sticky bottom bar (§11.6). In S2 the server's `registration` option
  /// is off and the first row shows; the rest is ready for S3's data.
  Widget _ctaBar(BuildContext context, EventDetail d, EventsOptions options) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final s = d.summary;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final now = widget.now ?? DateTime.now();

    String? hint;
    Color? hintColor;
    String label;
    VoidCallback? onPressed;
    IconData? icon;
    var hidden = false;

    if (!options.registration) {
      label = context.tr('events.cta.register');
      hint = context.tr('events.cta.soon');
    } else {
      switch (s.availability) {
        case EventAvailability.open:
          final from = s.fromPriceTzs;
          label = from == null || from == 0
              ? context.tr('events.cta.register')
              : context
                    .tr('events.cta.registerFrom')
                    .replaceFirst(
                      '{amount}',
                      formatCurrency(from, currency: s.currency),
                    );
          if (s.registrationClosesAt != null) {
            hint = context
                .tr('events.cta.closes')
                .replaceFirst(
                  '{date}',
                  eventDayChip(
                    s.registrationClosesAt!,
                    s.utcOffsetMinutes,
                    locale: lang,
                  ),
                );
          }
          onPressed = () => _register(d);
        case EventAvailability.closingSoon:
          label = context.tr('events.cta.register');
          icon = Icons.schedule;
          final closes = s.registrationClosesAt;
          hint = context
              .tr('events.cta.closingSoon')
              .replaceFirst(
                '{n}',
                '${closes == null ? 0 : daysUntil(closes, now)}',
              );
          hintColor = fuelTextColor(context);
          onPressed = () => _register(d);
        case EventAvailability.soldOut:
          label = context.tr('events.cta.soldOut');
          hint = context.tr('events.cta.soldOutHint');
        case EventAvailability.closed:
          label = context.tr('events.cta.closed');
        case EventAvailability.notYetOpen:
          final opens = s.registrationOpensAt;
          label = context
              .tr('events.cta.opens')
              .replaceFirst(
                '{date}',
                opens == null
                    ? '—'
                    : eventDayChip(opens, s.utcOffsetMinutes, locale: lang),
              );
        case EventAvailability.cancelled:
          label = context.tr('events.cta.cancelled');
        case EventAvailability.inProgress:
        case EventAvailability.completed:
          label = '';
          hidden = true;
      }
    }
    if (hidden) return const SizedBox.shrink(key: Key('event-cta-hidden'));

    return SafeArea(
      top: false,
      child: Container(
        key: const Key('event-cta-bar'),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outline)),
        ),
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: Text(
                  hint,
                  key: const Key('event-cta-hint'),
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(
                    color: hintColor ?? cs.onSurfaceVariant,
                    fontWeight: hintColor == null ? null : FontWeight.w600,
                  ),
                ),
              ),
            FFButton(
              key: const Key('event-cta'),
              label: label,
              fullWidth: true,
              icon: icon,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }

  void _showRouteImage(BuildContext context, EventDetail d) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(ctx.tr('events.detail.routeImage')),
            leading: IconButton(
              tooltip: ctx.tr('common.close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: InteractiveViewer(
            child: Center(
              child: FFRemoteImage(
                src: d.routeImageUrl!,
                fit: BoxFit.contain,
                fallback: EventImagePlaceholder(type: d.summary.type),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Long text with a "Read more" / "Show less" toggle after [collapsedLines].
class _Expandable extends StatelessWidget {
  const _Expandable({
    super.key,
    required this.text,
    required this.expanded,
    required this.collapsedLines,
    required this.moreLabel,
    required this.lessLabel,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final int collapsedLines;
  final String moreLabel;
  final String lessLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final style = tt.bodyMedium;
    return LayoutBuilder(
      builder: (context, c) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: style,
              maxLines: expanded ? null : collapsedLines,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              FFButton(
                label: expanded ? lessLabel : moreLabel,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                onPressed: onToggle,
              ),
          ],
        );
      },
    );
  }
}
