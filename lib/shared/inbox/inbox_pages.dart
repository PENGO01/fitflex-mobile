// The inbox: every message the signed-in user has had — bookings, payments,
// renewals, and messages from their gym and FitFlex — plus one message's
// page with its button. Used by members and gym owners alike.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../formatters.dart';
import '../friend_invites.dart';
import '../i18n.dart';
import 'inbox_controller.dart';

/// The bell with an unread count, opening the inbox.
class InboxBellButton extends StatelessWidget {
  const InboxBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    if (inbox == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) => IconButton(
        key: const Key('inbox-bell'),
        tooltip: context.tr('inbox.title'),
        onPressed: () => context.push('/inbox'),
        icon: Badge(
          isLabelVisible: inbox.unread > 0,
          label: Text(inbox.unread > 99 ? '99+' : '${inbox.unread}'),
          child: const Icon(Icons.notifications_none),
        ),
      ),
    );
  }
}

/// Today: the time; other days: day and month, in the app's language
/// ("19 Okt" in Swahili).
String _when(BuildContext context, DateTime? at) {
  if (at == null) return '';
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return sameDay
      ? DateFormat('HH:mm').format(at)
      : formatDayMonth(
          at,
          locale: FFLocaleScope.of(context).locale.languageCode,
        );
}

/// Where a message's button goes, for the signed-in role: members,
/// trainers, vendors and gyms each get their own screens.
String? routeForMessage(BuildContext context, InboxMessage m) {
  // An organisation's request is answered on its own screen, on any side.
  if (isB2BMemberRequest(m.type, m.data)) return b2bMemberRequestsRoute;
  final role =
      AppScope.of(context).auth.user?['userType']?.toString() ??
      AppScope.of(context).auth.role;
  // A FitFlex admin added them: a member's benefits; otherwise the message
  // says it all (no button).
  if (m.type == b2bAdminAddedType) {
    return adminAddedOpensBenefits(role, m.data) ? memberBenefitsRoute : null;
  }
  if (partnerSide(role) case final side?) {
    return partnerRouteFor(
      side: side,
      type: m.type,
      gymId: m.data['gymId']?.toString() ?? m.gymId,
      memberId: m.data['memberId']?.toString(),
      productId: m.data['productId']?.toString(),
      variant: m.data['variant']?.toString(),
      saleId: m.data['saleId']?.toString(),
      customerId: m.data['customerId']?.toString(),
      bannerId: (m.data['bannerId'] ?? m.data['item'])?.toString(),
      flashSaleId: (m.data['saleId'] ?? m.data['item'])?.toString(),
      refundId: m.data['refundId']?.toString(),
      purchaseId: m.data['purchaseId']?.toString(),
    );
  }
  if (role != 'member') return null;
  return memberRouteFor(
    deepLink: m.deepLink,
    type: m.type,
    gymId: m.gymId,
    trainerId: m.data['trainerId']?.toString(),
    planId: m.data['planId']?.toString(),
    bookingId: m.data['bookingId']?.toString(),
    eventId: m.data['eventId']?.toString(),
    orderId: m.data['orderId']?.toString(),
    registrationId: m.data['registrationId']?.toString(),
  );
}

/// The words on a message's button, for where it leads.
String inboxButtonLabel(BuildContext context, InboxMessage m) {
  final role =
      AppScope.of(context).auth.user?['userType']?.toString() ??
      AppScope.of(context).auth.role;
  final side = partnerSide(role);
  final link = isB2BMemberRequest(m.type, m.data)
      ? 'memberRequests'
      : m.type == b2bAdminAddedType
      ? (adminAddedOpensBenefits(role, m.data) ? 'benefits' : '')
      : side == null
      ? memberLinkFor(deepLink: m.deepLink, type: m.type)
      : partnerLinkFor(side: side, type: m.type);
  final key = 'inbox.open.${link.isEmpty ? 'message' : link}';
  final label = context.tr(key);
  return label == key ? context.tr('inbox.open.message') : label;
}

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  InboxCategory? _filter;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // After the first frame: loading notifies listeners, which mustn't
    // happen while the tree is building.
    final inbox = AppScope.of(context).inbox;
    WidgetsBinding.instance.addPostFrameCallback((_) => inbox?.load());
  }

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    final role =
        AppScope.of(context).auth.user?['userType']?.toString() ??
        AppScope.of(context).auth.role;
    // Members, and vendors and their staff (some staff have no Business
    // tab, where vendors also find it), choose their offers from here.
    final showSettings = role == 'member' || partnerSide(role) == 'vendor';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('inbox.title')),
        actions: [
          if (inbox != null)
            ListenableBuilder(
              listenable: inbox,
              builder: (context, _) => FFButton(
                key: const Key('inbox-read-all'),
                label: context.tr('inbox.markAllRead'),
                onPressed: inbox.unread == 0 ? null : inbox.markAllRead,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
              ),
            ),
          if (showSettings)
            IconButton(
              key: const Key('inbox-settings'),
              tooltip: context.tr('msgPrefs.title'),
              onPressed: () => context.push('/member/message-settings'),
              icon: const Icon(Icons.tune),
            ),
        ],
      ),
      body: inbox == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: inbox,
              builder: (context, _) => RefreshIndicator(
                onRefresh: inbox.load,
                child: _list(context, inbox),
              ),
            ),
    );
  }

  Widget _list(BuildContext context, InboxController inbox) {
    if (inbox.loading && inbox.messages.isEmpty) {
      return const Center(child: FFSpinner());
    }
    if (inbox.error != null && inbox.messages.isEmpty) {
      return ListView(
        children: [
          FFEmptyState(
            title: context.tr('inbox.loadFailed'),
            body: errorMessage(FFLocaleScope.of(context), inbox.error!),
            action: FFButton(
              label: context.tr('comms.retry'),
              onPressed: inbox.load,
            ),
          ),
        ],
      );
    }
    const filters = [
      null,
      InboxCategory.membership,
      InboxCategory.payments,
      InboxCategory.offers,
      InboxCategory.announcements,
    ];
    final shown = inbox.messages
        .where((m) => _filter == null || m.kind == _filter)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: FFTokens.spacingXs),
                  child: FFPill(
                    key: Key('inbox-filter-${f?.name ?? 'all'}'),
                    label: context.tr('inbox.filter.${f?.name ?? 'all'}'),
                    filled: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (shown.isEmpty)
          FFEmptyState(
            title: context.tr('inbox.empty.title'),
            body: context.tr('inbox.empty.body'),
          )
        else
          for (final m in shown) _MessageTile(message: m),
      ],
    );
  }
}

/// What a message shows: friend invitations are composed from their data so
/// the text follows the app language.
({String title, String body}) _text(BuildContext context, InboxMessage m) {
  if (m.isFriendInvitation) {
    final name = (m.data['inviterName']?.toString() ?? '').trim();
    final who = name.isEmpty ? context.tr('friendInvite.someone') : name;
    return (
      title: context.tr('friendInvite.cardTitle'),
      body: context.tr('friendInvite.cardBody').replaceFirst('{name}', who),
    );
  }
  // Some notices carry their own Swahili (vendor_low_stock,
  // trainer_booking_no_show…).
  return localisedNoticeText(
    lang: FFLocaleScope.of(context).locale.languageCode,
    data: m.data,
    title: m.title,
    body: m.body,
  );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});
  final InboxMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    final text = _text(context, m);
    final inbox = AppScope.of(context).inbox;
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        key: Key('inbox-${m.id}'),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        onTap: m.isFriendInvitation
            ? null
            : () => context.push('/inbox/${m.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: FFTokens.spacingSm),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: m.unread
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.senderName ?? context.tr('inbox.from.fitflex'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Text(
                        _when(context, m.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacing2xs),
                  Text(
                    text.title,
                    style: m.unread
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                  ),
                  Text(
                    text.body,
                    maxLines: m.isFriendInvitation ? null : 2,
                    overflow: m.isFriendInvitation
                        ? null
                        : TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  // Approve / Reject sit on the card itself.
                  if (m.isFriendInvitation && inbox != null)
                    FriendInvitationActions(message: m, inbox: inbox),
                  if (m.kind == InboxCategory.offers)
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                      child: FFBadge(
                        label: context.tr('inbox.filter.offers'),
                        tone: FFBadgeTone.brand,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One message, marked read on open, with its button.
class InboxMessagePage extends StatefulWidget {
  const InboxMessagePage({super.key, required this.messageId});
  final String messageId;

  @override
  State<InboxMessagePage> createState() => _InboxMessagePageState();
}

class _InboxMessagePageState extends State<InboxMessagePage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final inbox = AppScope.of(context).inbox;
    if (inbox == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (inbox.byId(widget.messageId) == null) await inbox.load();
      await inbox.markRead(widget.messageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('inbox.message'))),
      body: inbox == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: inbox,
              builder: (context, _) {
                final m = inbox.byId(widget.messageId);
                if (m == null) {
                  return inbox.loading
                      ? const Center(child: FFSpinner())
                      : FFEmptyState(title: context.tr('inbox.notFound'));
                }
                return _body(context, inbox, m);
              },
            ),
    );
  }

  Widget _body(BuildContext context, InboxController inbox, InboxMessage m) {
    final theme = Theme.of(context);
    final route = routeForMessage(context, m);
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          m.senderName ?? context.tr('inbox.from.fitflex'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(_text(context, m).title, style: theme.textTheme.titleLarge),
        if (m.createdAt != null)
          Text(
            // Month names in the app's language ("19 Okt 2026" in Swahili).
            formatDateTime(
              m.createdAt,
              locale: FFLocaleScope.of(context).locale.languageCode,
            ),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(_text(context, m).body, style: theme.textTheme.bodyLarge),
        if (m.isFriendInvitation)
          FriendInvitationActions(message: m, inbox: inbox),
        if (route != null) ...[
          const SizedBox(height: FFTokens.spacingLg),
          FFButton(
            key: const Key('inbox-cta'),
            label: m.ctaLabel ?? inboxButtonLabel(context, m),
            onPressed: () async {
              await inbox.click(m.id);
              // Member screens live in the member shell: go, like the rest
              // of the app does, rather than stacking the shell on the inbox.
              if (context.mounted) context.go(route);
            },
          ),
        ],
        if (m.kind == InboxCategory.offers) ...[
          const SizedBox(height: FFTokens.spacingLg),
          Text(
            context.tr('inbox.offersNote'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
