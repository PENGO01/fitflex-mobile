import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/run_metrics.dart' show formatPace;
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/friend_invites.dart';
import '../../shared/i18n.dart';
import '../../shared/social.dart';
import '../../shared/formatters.dart';

/// Friends & groups: the feed of what people shared, finding and following
/// people, and groups. Only mutual followers, group-mates and colleagues
/// ever see what a member shares.
class MemberCommunityPage extends StatelessWidget {
  const MemberCommunityPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr('community.title')),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.memberProfile),
        ),
        bottom: TabBar(
          tabs: [
            Tab(
              key: const Key('community-tab-feed'),
              text: context.tr('community.feed'),
            ),
            Tab(
              key: const Key('community-tab-explore'),
              text: context.tr('community.explore'),
            ),
            Tab(
              key: const Key('community-tab-people'),
              text: context.tr('community.people'),
            ),
            Tab(
              key: const Key('community-tab-groups'),
              text: context.tr('community.groups'),
            ),
          ],
        ),
      ),
      body: const TabBarView(
        children: [FeedTab(), FeedTab(explore: true), PeopleTab(), GroupsTab()],
      ),
    ),
  );
}

String errorText(BuildContext context, Object e) {
  final s = e.toString();
  for (final code in [
    'not_found',
    'company_only',
    'members_only',
    'last_admin',
    'group_full',
    'empty_comment',
    'invalid_name',
  ]) {
    if (s.contains(code)) return context.tr('community.error.$code');
  }
  return context.tr('community.error.generic');
}

/// Small buttons for rows (the theme's default is wide).
final compactButton = FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  visualDensity: VisualDensity.compact,
);

// ── Feed ─────────────────────────────────────────────────────────────────

/// Your feed (people you follow, friends, groups, company), or with
/// [explore] recent public posts from public profiles.
class FeedTab extends StatefulWidget {
  const FeedTab({super.key, this.explore = false});

  final bool explore;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  List<FeedItem>? _items;
  String? _next;
  bool _loadingMore = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final api = AppScope.of(context).api;
    try {
      if (more) setState(() => _loadingMore = true);
      final before = more ? _next : null;
      final res = widget.explore
          ? await api.explore(before: before)
          : await api.feed(before: before);
      final items = [
        for (final i in (res['items'] as List? ?? const []))
          if (i is Map) FeedItem.fromJson(i),
      ];
      if (!mounted) return;
      setState(() {
        _items = more ? [...?_items, ...items] : items;
        _next = res['next'] as String?;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => (_items ??= const [], _loadingMore = false));
    }
  }

  Future<void> _kudos(int i) async {
    final item = _items![i];
    final on = !item.youKudoed;
    setState(
      () => _items![i] = item.copyWith(
        youKudoed: on,
        kudos: item.kudos + (on ? 1 : -1),
      ),
    );
    try {
      final r = await AppScope.of(context).api.kudos(item.activity.id, on);
      if (mounted) {
        setState(
          () => _items![i] = item.copyWith(
            youKudoed: r['youKudoed'] == true,
            kudos: (r['kudos'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _items![i] = item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: FFSpinner(size: 32));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (items.isEmpty)
            FFEmptyState(
              key: Key(widget.explore ? 'explore-empty' : 'feed-empty'),
              title: context.tr(
                widget.explore
                    ? 'community.exploreEmptyTitle'
                    : 'community.feedEmptyTitle',
              ),
              body: context.tr(
                widget.explore
                    ? 'community.exploreEmptyBody'
                    : 'community.feedEmptyBody',
              ),
            ),
          for (final (i, item) in items.indexed)
            FeedCard(
              item: item,
              onKudos: () => _kudos(i),
              onOpen: () async {
                await context.push(
                  AppRoutes.memberSharedActivity.replaceFirst(
                    ':activityId',
                    Uri.encodeComponent(item.activity.id),
                  ),
                );
                if (mounted) _load();
              },
            ),
          if (_next != null)
            Center(
              child: FFButton(
                label: context.tr('community.more'),
                onPressed: _loadingMore ? null : () => _load(more: true),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
              ),
            ),
        ],
      ),
    );
  }
}

IconData sharedTypeIcon(String type) => switch (type) {
  'running' || 'jogging' => Icons.directions_run,
  'walking' || 'hiking' => Icons.directions_walk,
  'cycling' => Icons.directions_bike,
  'swimming' => Icons.pool,
  'strength' || 'functional' || 'hiit' => Icons.fitness_center,
  _ => Icons.bolt,
};

/// "5.20 km · 28:14 · 5:26 /km · 12 m climb"
String sharedStats(BuildContext context, SharedActivity a) {
  final secs =
      a.movingSeconds ??
      (a.durationMinutes != null ? a.durationMinutes! * 60 : null);
  String dur(int s) =>
      s >= 3600 ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m' : '${s ~/ 60} min';
  return [
    if ((a.distanceKm ?? 0) > 0) '${a.distanceKm!.toStringAsFixed(2)} km',
    if (secs != null) dur(secs),
    if ((a.distanceKm ?? 0) > 0.1 && a.movingSeconds != null)
      '${formatPace((a.movingSeconds! / a.distanceKm!).round())} /km',
    if ((a.elevationGainM ?? 0) >= 1)
      '${a.elevationGainM!.round()} m ${context.tr('run.climb').toLowerCase()}',
    if (a.steps != null && (a.distanceKm ?? 0) == 0)
      '${NumberFormat.decimalPattern().format(a.steps)} ${context.tr('activity.steps').toLowerCase()}',
  ].join(' · ');
}

class FeedCard extends StatelessWidget {
  const FeedCard({
    super.key,
    required this.item,
    required this.onKudos,
    required this.onOpen,
  });

  final FeedItem item;
  final VoidCallback onKudos;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = item.activity;
    final you = item.owner.relationship == Relationship.you;
    return FFCard(
      key: Key('feed-${a.id}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('feed-owner-${a.id}'),
              // The poster's profile, to follow them or see more.
              onTap: you ? null : () => openPerson(context, item.owner.id),
              child: Row(
                children: [
                  FFAvatar(name: item.owner.name, size: FFAvatarSize.sm),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          you ? context.tr('community.you') : item.owner.name,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          context.localDayTime(a.startedAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!you && item.owner.relationship == Relationship.none)
                    Text(
                      context.tr('community.notFollowing'),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                Icon(
                  sharedTypeIcon(a.type),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: FFTokens.spacingXs),
                Expanded(
                  child: Text(
                    (a.title ?? '').isNotEmpty
                        ? a.title!
                        : context.tr('activity.type.${a.type}'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(sharedStats(context, a), style: theme.textTheme.bodyMedium),
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              children: [
                TextButton.icon(
                  key: Key('kudos-${a.id}'),
                  onPressed: you ? null : onKudos,
                  icon: Icon(
                    item.youKudoed ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18,
                  ),
                  label: Text('${item.kudos}'),
                ),
                FFButton(
                  label: '${item.comments}',
                  onPressed: onOpen,
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  icon: Icons.chat_bubble_outline,
                ),
                if (you && item.views != null) ...[
                  const Spacer(),
                  Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: FFTokens.spacingXs),
                  Text(
                    context
                        .tr('community.views')
                        .replaceAll('{n}', '${item.views}'),
                    key: Key('views-${a.id}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── People ───────────────────────────────────────────────────────────────

class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  List<SocialPerson> _friends = const [],
      _following = const [],
      _followers = const [];
  List<SocialPerson>? _found;
  // Result of searching by email / phone, and the invitations this member sent.
  Map<String, dynamic>? _contactFound;
  ({String? email, String? phone})? _contactQuery;
  List<Map<String, dynamic>> _sentRequests = const [];
  bool _contactBusy = false;
  bool _loaded = false;
  bool _started = false;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SocialPerson> _people(Object? v) => [
    for (final p in (v as List? ?? const []))
      if (p is Map) SocialPerson.fromJson(p),
  ];

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final r = await Future.wait([api.connections()]);
      Object? sent;
      try {
        sent = (await api.friendInvitations())['outgoing'];
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sentRequests = [
          for (final i in (sent as List? ?? const []))
            if (i is Map) i.cast<String, dynamic>(),
        ];
        _friends = _people(r[0]['friends']);
        _following = _people(r[0]['following']);
        _followers = _people(r[0]['followers']);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  /// An email address or a mobile number, as typed; null for a name or code.
  static ({String? email, String? phone})? _asContact(String q) {
    if (q.contains('@')) return (email: q, phone: null);
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^\+?[\d\s().-]+$').hasMatch(q) && digits.length >= 9) {
      return (email: null, phone: q);
    }
    return null;
  }

  /// Pick one person from the phone's address book and search for them.
  /// Only the chosen contact's number or email is read; nothing else leaves
  /// the phone, and nothing is uploaded until the search itself.
  Future<void> _pickFromContacts() async {
    final t = context.tr;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        messenger.showSnackBar(
          SnackBar(content: Text(t('community.contactsDenied'))),
        );
        return;
      }
      final picked = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.phone, ContactProperty.email},
      );
      if (picked == null || !mounted) return;
      final options = <String>[
        for (final p in picked.phones)
          if (p.number.trim().isNotEmpty) p.number.trim(),
        for (final e in picked.emails)
          if (e.address.trim().isNotEmpty) e.address.trim(),
      ];
      if (options.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(t('community.contactNoNumber'))),
        );
        return;
      }
      var choice = options.first;
      if (options.length > 1) {
        final chosen = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final o in options)
                  ListTile(
                    leading: Icon(
                      o.contains('@') ? Icons.email_outlined : Icons.phone,
                    ),
                    title: Text(o),
                    onTap: () => Navigator.pop(ctx, o),
                  ),
              ],
            ),
          ),
        );
        if (chosen == null || !mounted) return;
        choice = chosen;
      }
      _search.text = choice;
      await _find();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(t('community.contactsFailed'))),
      );
    }
  }

  Future<void> _findContact(({String? email, String? phone}) c) async {
    final api = AppScope.of(context).api;
    setState(() {
      _found = null;
      _contactBusy = true;
    });
    try {
      final r = await api.friendLookup(email: c.email, phone: c.phone);
      if (!mounted) return;
      setState(() {
        _contactQuery = c;
        _contactFound = (r['result'] as Map?)?.cast<String, dynamic>();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contactQuery = c;
        _contactFound = null;
      });
      FFSnack.error(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _contactBusy = false);
    }
  }

  /// Request to a member, or a share link for someone not on FitFlex.
  /// Why FitFlex did not send an invitation it tried to, in the member's
  /// language. Null when the server did not try (sending is off).
  String? _notSentReason(Map<String, dynamic> delivery) {
    if (delivery.isEmpty) return null;
    final t = context.tr;
    final reasons = <String>{};
    for (final v in delivery.values) {
      final text = v.toString();
      if (text == 'sent') continue;
      final code = text.startsWith('skipped:') ? text.substring(8) : text;
      reasons.add(switch (code) {
        'sms_not_configured' => t('friendInvite.reason.smsNotSetUp'),
        'whatsapp_not_available' ||
        'whatsapp_not_configured' => t('friendInvite.reason.whatsappNotSetUp'),
        'whatsapp_template_not_approved' => t(
          'friendInvite.reason.templateNotApproved',
        ),
        'daily_limit' => t('friendInvite.reason.dailyLimit'),
        'invalid_phone' || 'no_phone' => t('friendInvite.reason.badNumber'),
        _ => t('friendInvite.reason.failed'),
      });
    }
    return reasons.isEmpty ? null : reasons.join(' ');
  }

  Future<void> _invite({String? userId}) async {
    final api = AppScope.of(context).api;
    final c = _contactQuery;
    final t = context.tr;
    final messenger = ScaffoldMessenger.of(context);
    final locale = FFLocaleScope.of(context).locale.languageCode;
    setState(() => _contactBusy = true);
    try {
      final r = await api.inviteFriend(
        userId: userId,
        email: userId == null ? c?.email : null,
        phone: userId == null ? c?.phone : null,
        locale: locale,
      );
      final share = (r['share'] as Map?)?.cast<String, dynamic>();
      final delivery = (r['delivery'] as Map?)?.cast<String, dynamic>() ?? {};
      final sentBySms = delivery['sms'] == 'sent';
      final sentByWhatsapp = delivery['whatsapp'] == 'sent';
      if (sentBySms || sentByWhatsapp) {
        // FitFlex sent it from its approved sender; "sent" means the
        // provider accepted it, not that it arrived.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              t(
                sentByWhatsapp && sentBySms
                    ? 'friendInvite.sentBoth'
                    : sentByWhatsapp
                    ? 'friendInvite.sentWhatsapp'
                    : 'friendInvite.sentSms',
              ),
            ),
          ),
        );
      } else if (delivery.values.any((v) => v == 'skipped:recently_sent')) {
        messenger.showSnackBar(
          SnackBar(content: Text(t('friendInvite.alreadySent'))),
        );
      } else if (share != null && mounted) {
        // Not sent by FitFlex (off, failed or capped): the member picks the
        // app and sends it themselves. If the server tried and could not,
        // say why first, so it is visible while the share sheet is open.
        final why = _notSentReason(delivery);
        if (why != null) {
          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              content: Text('${t('friendInvite.notSentByFitflex')} $why'),
            ),
          );
        }
        await shareFriendInvite(
          context,
          text: share['text'].toString(),
          link: share['link'].toString(),
          subject: share['subject']?.toString(),
        );
        if (why == null) {
          messenger.showSnackBar(
            SnackBar(content: Text(t('friendInvite.created'))),
          );
        }
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(t('friendInvite.requestSent'))),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(errorText(context, e)),
            action: SnackBarAction(
              label: t('comms.retry'),
              onPressed: () => _invite(userId: userId),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _contactBusy = false);
    }
    if (mounted) {
      await _load();
      if (c != null) await _findContact(c);
    }
  }

  Widget _contactCard() {
    final theme = Theme.of(context);
    final t = context.tr;
    final r = _contactFound;
    if (r == null) return const SizedBox.shrink();
    final isMember = r['kind'] == 'member';
    final rel = r['relationship']?.toString() ?? 'none';
    final pending = (r['request'] as Map?)?['status'] == 'pending';
    final String title;
    final String hint;
    Widget? action;
    if (isMember) {
      title = r['name']?.toString() ?? '';
      if (rel == 'friends') {
        hint = t('community.friends');
      } else if (pending) {
        hint = t('friendInvite.status.pending');
      } else {
        hint = t('friendInvite.onFitflex');
        action = FilledButton.tonal(
          key: const Key('friend-request-send'),
          style: compactButton,
          onPressed: _contactBusy
              ? null
              : () => _invite(userId: r['userId'].toString()),
          child: Text(t('friendInvite.sendRequest')),
        );
      }
    } else {
      title = t('friendInvite.notOnFitflex');
      hint = t('friendInvite.shareHint');
      action = FilledButton.icon(
        key: const Key('friend-invite-share'),
        style: compactButton,
        onPressed: _contactBusy ? null : () => _invite(),
        icon: const Icon(Icons.share, size: 18),
        label: Text(t('friendInvite.invite')),
      );
    }
    return FFCard(
      key: const Key('contact-result'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ?action,
            ],
          ),
          const SizedBox(height: FFTokens.spacing2xs),
          Text(hint, style: theme.textTheme.bodySmall),
          if (!isMember) ...[
            const SizedBox(height: FFTokens.spacing2xs),
            Text(
              t(
                (r['delivery'] as Map?)?['sms'] == true ||
                        (r['delivery'] as Map?)?['whatsapp'] == true
                    ? 'friendInvite.fitflexSendsNote'
                    : 'friendInvite.smsNote',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Who a sent invitation was for: their (masked) name, else the number or
  /// email you invited, else just the kind of contact.
  String _sentTitle(Map<String, dynamic> i, String Function(String) t) {
    final name = i['name']?.toString() ?? '';
    if (name.isNotEmpty) return name;
    final contact = i['contact']?.toString() ?? '';
    if (contact.isNotEmpty) return contact;
    return t('friendInvite.linkShared.${i['contactType'] ?? 'email'}');
  }

  /// "Sent by FitFlex on WhatsApp · 17 Oct", or SMS, or "no WhatsApp, sent by SMS".
  String? _sentLine(Map<String, dynamic> i, String Function(String) t) {
    final by = [
      for (final c in (i['sentBy'] as List? ?? const [])) c.toString(),
    ];
    if (by.isEmpty) return null;
    final at = DateTime.tryParse(i['sentAt']?.toString() ?? '')?.toLocal();
    final when = at == null ? '' : ' · ${DateFormat('d MMM').format(at)}';
    final key = i['whatsappFailed'] == true && by.contains('sms')
        ? 'friendInvite.sentBy.smsInstead'
        : by.contains('whatsapp') && by.contains('sms')
        ? 'friendInvite.sentBy.both'
        : by.contains('whatsapp')
        ? 'friendInvite.sentBy.whatsapp'
        : 'friendInvite.sentBy.sms';
    // What the SMS provider later reported; nothing until it has (or when the
    // server does not track it).
    final delivery = switch (i['smsDelivery']) {
      'delivered' => ' · ${t('friendInvite.smsDelivery.delivered')}',
      'undelivered' => ' · ${t('friendInvite.smsDelivery.undelivered')}',
      _ => '',
    };
    return '${t(key)}$when$delivery';
  }

  Widget _sentRequestsSection() {
    final t = context.tr;
    final api = AppScope.of(context).api;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(t('friendInvite.sentTitle')),
        for (final i in _sentRequests)
          FFCard(
            key: Key('sent-${i['id']}'),
            margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sentTitle(i, t),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      // What you typed, so you can tell who it was for.
                      if ((i['contact']?.toString() ?? '').isNotEmpty &&
                          (i['name']?.toString() ?? '').isNotEmpty)
                        Text(
                          i['contact'].toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      // FitFlex sent it for you: say how, and when.
                      if (_sentLine(i, t) case final line?)
                        Text(
                          line,
                          key: Key('sent-by-${i['id']}'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (i['status'] == 'pending')
                  FFButton(
                    key: Key('sent-cancel-${i['id']}'),
                    label: t('friendInvite.cancel'),
                    onPressed: () => _act(
                      () => api.revokeFriendInvitation(i['id'].toString()),
                      t('friendInvite.cancelled'),
                    ),
                    variant: FFButtonVariant.ghost,
                    size: FFButtonSize.sm,
                  ),
                FFBadge(
                  label: t('friendInvite.status.${i['status']}'),
                  tone: i['status'] == 'accepted'
                      ? FFBadgeTone.success
                      : FFBadgeTone.gray,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.isEmpty) {
      return setState(() {
        _found = null;
        _contactFound = null;
        _contactQuery = null;
      });
    }
    final contact = _asContact(q);
    if (contact != null) return _findContact(contact);
    setState(() {
      _contactFound = null;
      _contactQuery = null;
    });
    final api = AppScope.of(context).api;
    // Invite codes are 8 letters/digits; anything else searches by name.
    try {
      final r = await api.findPeople(q: q);
      if (mounted) setState(() => _found = _people(r['people']));
    } catch (_) {
      if (mounted) setState(() => _found = const []);
    }
  }

  Future<void> _act(Future<Object?> Function() call, String done) async {
    final messenger = FFSnack.of(context);
    final failed = errorText(context, '');
    try {
      await call();
      messenger.success(done);
    } catch (e) {
      messenger.error(failed);
    }
    await _load();
    if (_found != null) await _find();
  }

  Widget _personTile(SocialPerson p) {
    final api = AppScope.of(context).api;
    final t = context.tr;
    final (label, action) = switch (p.relationship) {
      Relationship.friends => (t('community.friends'), null),
      Relationship.following => (t('community.followingLabel'), null),
      Relationship.followsYou => (
        t('community.followBack'),
        () => _act(() => api.follow(p.id), t('community.followedToast')),
      ),
      _ => (
        t('community.follow'),
        () => _act(() => api.follow(p.id), t('community.followedToast')),
      ),
    };
    return FFCard(
      key: Key('person-${p.id}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Row(
        children: [
          FFAvatar(name: p.name, size: FFAvatarSize.sm),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: InkWell(
              onTap: () => openPerson(context, p.id),
              child: Text(
                p.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          if (action != null)
            FilledButton.tonal(
              key: Key('follow-${p.id}'),
              style: compactButton,
              onPressed: action,
              child: Text(label),
            )
          else
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          PopupMenuButton<String>(
            key: Key('person-menu-${p.id}'),
            onSelected: (v) => switch (v) {
              'unfollow' => _act(
                () => api.unfollow(p.id),
                t('community.unfollowedToast'),
              ),
              'remove' => _act(
                () => api.removeFollower(p.id),
                t('community.removedToast'),
              ),
              'block' => _act(
                () => api.block(p.id),
                t('community.blockedToast'),
              ),
              'report' => _act(
                () => api.report('user', p.id),
                t('community.reportedToast'),
              ),
              _ => null,
            },
            itemBuilder: (_) => [
              if (p.relationship == Relationship.friends ||
                  p.relationship == Relationship.following)
                PopupMenuItem(
                  value: 'unfollow',
                  child: Text(t('community.unfollow')),
                ),
              if (p.relationship == Relationship.friends ||
                  p.relationship == Relationship.followsYou)
                PopupMenuItem(
                  value: 'remove',
                  child: Text(t('community.removeFollower')),
                ),
              PopupMenuItem(value: 'block', child: Text(t('community.block'))),
              PopupMenuItem(
                value: 'report',
                child: Text(t('community.report')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: FFSpinner(size: 32));
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFTextField(
            key: const Key('people-search'),
            controller: _search,
            hint: context.tr('community.searchHint'),
            textInputAction: TextInputAction.search,
            onFieldSubmitted: (_) => _find(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('people-pick-contact'),
                  tooltip: context.tr('community.fromContacts'),
                  icon: const Icon(Icons.contacts_outlined),
                  onPressed: _pickFromContacts,
                ),
                IconButton(
                  tooltip: context.tr('a11y.search'),
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _find,
                ),
              ],
            ),
          ),
          if (_contactBusy) const LinearProgressIndicator(),
          if (_contactFound != null) ...[
            FFSectionTitle(context.tr('community.results')),
            _contactCard(),
          ],
          if (_found != null) ...[
            FFSectionTitle(context.tr('community.results')),
            if (_found!.isEmpty)
              Text(
                context.tr('community.noResults'),
                style: theme.textTheme.bodySmall,
              ),
            for (final p in _found!) _personTile(p),
          ],
          if (_sentRequests.isNotEmpty) _sentRequestsSection(),
          if (_followers.isNotEmpty) ...[
            FFSectionTitle(context.tr('community.followsYou')),
            for (final p in _followers) _personTile(p),
          ],
          FFSectionTitle(context.tr('community.friends')),
          if (_friends.isEmpty)
            Text(
              context.tr('community.noFriends'),
              style: theme.textTheme.bodySmall,
            ),
          for (final p in _friends) _personTile(p),
          if (_following.isNotEmpty) ...[
            FFSectionTitle(context.tr('community.waitingTitle')),
            for (final p in _following) _personTile(p),
          ],
        ],
      ),
    );
  }
}

// ── Groups ───────────────────────────────────────────────────────────────

class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  List<SocialGroup>? _mine;
  List<SocialGroup> _found = const [];
  bool _started = false;
  final _q = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<SocialGroup> _groups(Object? v) => [
    for (final g in (v as List? ?? const []))
      if (g is Map) SocialGroup.fromJson(g),
  ];

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final r = await Future.wait([
        api.myGroups(),
        api.discoverGroups(q: _q.text.trim()),
      ]);
      if (mounted) {
        setState(
          () => (
            _mine = _groups(r[0]['groups']),
            _found = _groups(r[1]['groups']),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _mine ??= const []);
    }
  }

  Future<void> _join({String? groupId, String? code}) async {
    final messenger = ScaffoldMessenger.of(context);
    final messengerSnack = FFSnack.of(context);
    final t = context.tr;
    try {
      final r = await AppScope.of(
        context,
      ).api.joinGroup(groupId: groupId, inviteCode: code);
      final g = SocialGroup.fromJson(r['group'] as Map? ?? const {});
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t(g.isPending ? 'community.requestSent' : 'community.joinedToast'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        messengerSnack.error(errorText(context, e));
      }
    }
    await _load();
  }

  Future<void> _joinByCode() async {
    final code = await _askText(
      context,
      title: context.tr('community.joinByCode'),
      hint: 'ABCD1234',
    );
    if (code != null && code.trim().isNotEmpty) await _join(code: code.trim());
  }

  Future<void> _create() async {
    final created = await showGroupForm(
      context,
      onSave: (body) async {
        final r = await AppScope.of(context).api.createMyGroup(body);
        return SocialGroup.fromJson(r['group'] as Map? ?? const {});
      },
    );
    if (created != null) {
      await _load();
      if (mounted) openGroup(context, created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    if (mine == null) return const Center(child: FFSpinner(size: 32));
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Row(
            children: [
              Expanded(
                child: FFButton(
                  key: const Key('group-create'),
                  label: context.tr('community.createGroup'),
                  onPressed: _create,
                  icon: Icons.add,
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: FFButton(
                  key: const Key('group-join-code'),
                  label: context.tr('community.joinByCode'),
                  onPressed: _joinByCode,
                  variant: FFButtonVariant.secondary,
                  icon: Icons.vpn_key_outlined,
                ),
              ),
            ],
          ),
          FFSectionTitle(context.tr('community.myGroups')),
          if (mine.isEmpty)
            Text(
              context.tr('community.noGroups'),
              style: theme.textTheme.bodySmall,
            ),
          for (final g in mine)
            FFActionTile(
              key: Key('group-${g.id}'),
              icon: Icons.groups_outlined,
              title: g.name,
              subtitle: [
                context
                    .tr('community.members')
                    .replaceAll('{n}', '${g.memberCount}'),
                if (g.isPending) context.tr('community.pending'),
                if (g.role == 'admin') context.tr('community.admin'),
              ].join(' · '),
              onTap: () async {
                await openGroup(context, g.id);
                _load();
              },
            ),
          FFSectionTitle(context.tr('community.findGroups')),
          FFTextField(
            controller: _q,
            hint: context.tr('community.findGroupsHint'),
            onFieldSubmitted: (_) => _load(),
            prefixIcon: const Icon(Icons.search),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (_found.isEmpty)
            Text(
              context.tr('community.noDiscover'),
              style: theme.textTheme.bodySmall,
            ),
          for (final g in _found)
            FFCard(
              key: Key('discover-${g.id}'),
              margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: theme.textTheme.titleSmall),
                        Text(
                          [
                            context
                                .tr('community.members')
                                .replaceAll('{n}', '${g.memberCount}'),
                            context.tr(
                              g.joinPolicy == 'open'
                                  ? 'community.openToJoin'
                                  : 'community.needsApproval',
                            ),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    style: compactButton,
                    onPressed: () => _join(groupId: g.id),
                    child: Text(
                      context.tr(
                        g.joinPolicy == 'open'
                            ? 'community.join'
                            : 'community.askToJoin',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> openPerson(BuildContext context, String userId) => context.push(
  AppRoutes.memberPerson.replaceFirst(':userId', Uri.encodeComponent(userId)),
);

Future<void> openGroup(BuildContext context, String id) => context.push(
  AppRoutes.memberGroup.replaceFirst(':groupId', Uri.encodeComponent(id)),
);

Future<String?> _askText(
  BuildContext context, {
  required String title,
  String? hint,
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: FFTextField(
        key: const Key('ask-text'),
        controller: c,
        hint: hint,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('trainer.cancel')),
        ),
        FilledButton(
          key: const Key('ask-text-ok'),
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(ctx.tr('audience.done')),
        ),
      ],
    ),
  );
}

/// Create or edit a group. [onSave] sends it and returns the saved group.
Future<SocialGroup?> showGroupForm(
  BuildContext context, {
  SocialGroup? existing,
  required Future<SocialGroup> Function(Map<String, dynamic> body) onSave,
}) => showModalBottomSheet<SocialGroup>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _GroupForm(existing: existing, onSave: onSave),
);

class _GroupForm extends StatefulWidget {
  const _GroupForm({this.existing, required this.onSave});

  final SocialGroup? existing;
  final Future<SocialGroup> Function(Map<String, dynamic> body) onSave;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late bool _open = widget.existing?.joinPolicy == 'open';
  late bool _listed = widget.existing?.discoverable ?? false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => (_busy = true, _error = null));
    try {
      final g = await widget.onSave({
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'joinPolicy': _open ? 'open' : 'approval',
        'discoverable': _listed,
      });
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (mounted) {
        setState(() => (_busy = false, _error = errorText(context, e)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
              widget.existing == null
                  ? 'community.createGroup'
                  : 'community.editGroup',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(message: _error!, tone: FFAlertTone.error),
            ),
          FFTextField(
            key: const Key('group-name'),
            controller: _name,
            label: context.tr('community.groupName'),
            maxLength: 60,
          ),
          FFTextField(
            controller: _desc,
            label: context.tr('community.groupDescription'),
            maxLines: 2,
            maxLength: 300,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _open,
            onChanged: (v) => setState(() => _open = v),
            title: Text(context.tr('community.openToJoin')),
            subtitle: Text(context.tr('community.openHint')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _listed,
            onChanged: (v) => setState(() => _listed = v),
            title: Text(context.tr('community.listed')),
            subtitle: Text(context.tr('community.listedHint')),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('group-save'),
            label: context.tr('community.saveGroup'),
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    ),
  );
}
