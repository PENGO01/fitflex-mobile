import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../pending_org_invite.dart';
import 'persona_switcher.dart';
import 'verify_identifier.dart';
import '../components/components.dart';
import '../payment_labels.dart';
import '../formatters.dart';

/// Where an invitation link opens (the web build of this app).
const kInviteLinkBase = 'https://fitflex-af-app.web.app';

/// The token goes after `#`, so browsers never send it to the server (or
/// its logs); the app keeps it on the device and drops it from the address.
String inviteLink(String token) =>
    '$kInviteLinkBase/#${AppRoutes.invitations}?token=${Uri.encodeQueryComponent(token)}';

String inviteRoleLabel(BuildContext context, Object? role) {
  switch (role?.toString()) {
    case 'staff':
      return context.tr('role.staff');
    case 'trainer':
      return context.tr('role.trainer');
    default:
      return context.tr('role.member');
  }
}

/// Message for an invitation API failure the person can act on.
String inviteErrorMessage(BuildContext context, Object error) {
  final code = error is ApiException ? error.code : null;
  final key = switch (code) {
    'identifier_not_verified' => 'invite.errNotVerified',
    'trainer_persona_required' => 'invite.errTrainerFirst',
    'already_staff_elsewhere' => 'invite.errStaffElsewhere',
    'already_a_member' => 'invite.errAlreadyMember',
    'already_owner' => 'invite.errAlreadyMember',
    'invitation_not_open' => 'invite.errNotOpen',
    'invitation_not_found' => 'invite.errNotFound',
    'one_phone_or_email_required' => 'invite.errContact',
    'lookup_rate_limited' || 'lookup_cooldown' => 'invite.errTooManyLookups',
    'resend_too_soon' || 'resend_limit_reached' => 'invite.errResend',
    'owner_only' => 'invite.errOwnerOnly',
    _ => null,
  };
  return key != null
      ? context.tr(key)
      : errorMessage(FFLocaleScope.of(context), error);
}

// ── Invited person ──────────────────────────────────────────────────────────

/// Profile tile shown only while the Person has open invitations.
class InvitationsTile extends StatelessWidget {
  const InvitationsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.invitations.isEmpty) return const SizedBox.shrink();
        return FFActionTile(
          key: const Key('invitations-tile'),
          icon: Icons.mail_outline,
          title: context.tr('invite.inboxTitle'),
          subtitle: context
              .tr('invite.inboxCount')
              .replaceAll('{n}', '${auth.invitations.length}'),
          onTap: () => context.push(AppRoutes.invitations),
        );
      },
    );
  }
}

/// The Person's open invitations. With [token] (from a link) it first opens
/// that invitation, which only works once they have verified the phone or
/// email it was sent to.
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key, this.token});

  final String? token;

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  bool _loading = true;
  String? _busyId;
  String? _notice;
  // Set when the link was sent to a mobile number or email not verified here.
  String? _needsVerified;

  // The link's token: given directly (tests) or kept on the device when the
  // link was opened. Held here so a retry after verifying can reuse it.
  String? _token;
  bool _tokenRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    String? notice;
    String? needsVerified;
    if (!_tokenRead) {
      _tokenRead = true;
      final kept = await PendingOrgInvite.take();
      _token = widget.token ?? kept;
      if (!mounted) return;
    }
    final token = _token;
    if (token != null && token.isNotEmpty) {
      try {
        await scope.api.openInvitation(token);
      } catch (e) {
        if (mounted) notice = inviteErrorMessage(context, e);
        if (e is ApiException &&
            e.code == 'identifier_not_verified' &&
            e.body is Map) {
          needsVerified = (e.body as Map)['identifierType']?.toString();
        }
      }
    }
    await scope.auth.refreshInvitations();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notice = notice;
      _needsVerified = needsVerified;
    });
  }

  Future<void> _verifyThenRetry(String type) async {
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VerifyIdentifierScreen(type: type)),
    );
    if (verified == true && mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  Future<void> _respond(Map<String, dynamic> invitation, bool accept) async {
    final scope = AppScope.of(context);
    final messenger = FFSnack.of(context);
    final id = invitation['id'].toString();
    setState(() => _busyId = id);
    try {
      if (!accept) {
        await scope.api.declineInvitation(id);
        await scope.auth.refreshInvitations();
        if (mounted) {
          messenger.info(context.tr('invite.declined'));
        }
        return;
      }
      final res = await scope.api.acceptInvitation(id);
      await scope.auth.refreshInvitations();
      await scope.auth.refreshPersonas();
      if (!mounted) return;
      messenger.success(context.tr('invite.accepted'));
      // A new role (for example gym staff): continue as it.
      final personaId = res['personaId']?.toString();
      final canSwitch = scope.auth.switchablePersonas.any(
        (p) => p['id'] == personaId,
      );
      if (personaId != null && canSwitch) {
        await switchToPersona(context, personaId);
      }
    } catch (e) {
      if (mounted) {
        messenger.error(inviteErrorMessage(context, e));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('invite.inboxTitle'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            if (_loading) {
              return const Center(child: FFSpinner(size: 32));
            }
            final items = auth.invitations;
            return ListView(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                    child: Text(
                      _notice!,
                      key: const Key('invitations-notice'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                if (_needsVerified != null && auth.identifiersEnabled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                    child: FFButton(
                      key: const Key('invitations-verify'),
                      label: context.tr(
                        _needsVerified == 'phone'
                            ? 'verify.phoneTitle'
                            : 'verify.emailTitle',
                      ),
                      onPressed: () => _verifyThenRetry(_needsVerified!),
                    ),
                  ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingLg),
                    child: Text(
                      context.tr('invite.inboxEmpty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final inv in items)
                  _InvitationCard(
                    invitation: inv,
                    busy: _busyId == inv['id'],
                    onAccept: () => _respond(inv, true),
                    onDecline: () => _respond(inv, false),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final Map<String, dynamic> invitation;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = invitation['plan'];
    final paid = invitation['paidAmountTzs'];
    final id = invitation['id'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              invitation['orgName']?.toString() ?? context.tr('invite.aGym'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              context
                  .tr('invite.asRole')
                  .replaceAll(
                    '{role}',
                    inviteRoleLabel(context, invitation['role']),
                  ),
            ),
            if (plan is Map) ...[
              const SizedBox(height: 4),
              Text(
                context
                    .tr('invite.planLine')
                    .replaceAll(
                      '{tier}',
                      passTierLabel(context, plan['tier'], fallback: ''),
                    )
                    .replaceAll(
                      '{end}',
                      context.localDate(plan['endDate'], fallback: ''),
                    ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (paid is num && paid > 0)
              Text(
                context
                    .tr('invite.paidLine')
                    .replaceAll('{amount}', paid.toStringAsFixed(0)),
                style: theme.textTheme.bodySmall,
              ),
            if (invitation['message'] != null) ...[
              const SizedBox(height: 4),
              Text(
                invitation['message'].toString(),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: FFTokens.spacingSm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FFButton(
                  key: Key('decline-$id'),
                  label: context.tr('invite.decline'),
                  onPressed: busy ? null : onDecline,
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                FFButton(
                  key: Key('accept-$id'),
                  label: context.tr('invite.accept'),
                  onPressed: busy ? null : onAccept,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Organisation: invite a person ───────────────────────────────────────────

const _staffScopes = [
  'members',
  'checkins',
  'payments',
  'trainers',
  'gyms',
  'shop',
  'communications',
];

String _scopeLabel(BuildContext context, String scope) => switch (scope) {
  'members' => context.tr('owner.members'),
  'checkins' => context.tr('owner.checkin'),
  'payments' => context.tr('owner.earnings'),
  'trainers' => context.tr('owner.trainers'),
  'gyms' => context.tr('owner.manageGyms'),
  'shop' => context.tr('owner.shop'),
  'communications' => context.tr('comms.title'),
  _ => scope,
};

/// The request body for an invitation, from what the form collected.
/// One contact (an email if it contains '@', otherwise a phone); for a member
/// the plan runs from [today], the payment date.
Map<String, dynamic> buildInvitationBody({
  required String role,
  required String contact,
  List<String> aclPermissions = const [],
  String durationUnit = 'M',
  String tier = 'basic',
  num? paidAmount,
  required DateTime today,
  String orgType = 'gym',
  String vendorRole = 'inventory_manager',
  List<String> vendorPermissions = const [],
}) {
  final value = contact.trim();
  final body = <String, dynamic>{
    'role': role,
    if (value.contains('@')) 'email': value else 'phone': value,
  };
  if (orgType == 'vendor') {
    // A shop's staff carry the shop's own role and permissions.
    body['vendorRole'] = vendorRole;
    body['permissions'] = vendorPermissions;
    return body;
  }
  if (role == 'staff') body['aclPermissions'] = aclPermissions;
  if (role == 'member') {
    final start = DateTime(today.year, today.month, today.day);
    final end = switch (durationUnit) {
      'D' => start.add(const Duration(days: 1)),
      'W' => start.add(const Duration(days: 7)),
      _ => DateTime(start.year, start.month + 1, start.day),
    };
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    body.addAll({
      'durationUnit': durationUnit,
      'startDate': dateOnly(start),
      'endDate': dateOnly(end),
      'tier': tier,
      if (paidAmount != null && paidAmount > 0) 'paidAmount': paidAmount,
    });
  }
  return body;
}

const _vendorRoles = {
  'admin': 'vendor.roleAdmin',
  'inventory_manager': 'vendor.roleInventory',
  'orders_manager': 'vendor.roleOrders',
  'sales': 'vendor.roleSales',
  'customer_care': 'vendor.roleCare',
};

const _vendorPermissions = [
  'products',
  'orders',
  'customers',
  'reports',
  'payments',
  'staff',
];

/// Invite a person to [gymId] as [role]. Returns true once an invitation was
/// sent. Replaces the "create with a PIN" forms when invitations are on.
/// With [orgType] 'vendor', [gymId] is the vendor's id and the sheet asks for
/// the shop's staff role and permissions.
Future<bool> openInvitePersonSheet(
  BuildContext context, {
  required String gymId,
  required String role,
  String orgType = 'gym',
  bool vendorSales = false,
  bool vendorPurchases = false,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _InvitePersonSheet(
      gymId: gymId,
      role: role,
      orgType: orgType,
      vendorSales: vendorSales,
      vendorPurchases: vendorPurchases,
    ),
  );
  return sent == true;
}

class _InvitePersonSheet extends StatefulWidget {
  const _InvitePersonSheet({
    required this.gymId,
    required this.role,
    this.orgType = 'gym',
    this.vendorSales = false,
    this.vendorPurchases = false,
  });

  final String gymId;
  final String role;
  final String orgType;

  /// S3: offer the shop's `sales` permission (walk-in sales on).
  final bool vendorSales;

  /// S9: offer `purchases` (the purchases tool on).
  final bool vendorPurchases;

  @override
  State<_InvitePersonSheet> createState() => _InvitePersonSheetState();
}

class _InvitePersonSheetState extends State<_InvitePersonSheet> {
  final _contact = TextEditingController();
  final _amount = TextEditingController();
  final _scopes = <String>{};
  final _vendorPerms = <String>{'products'};
  String _vendorRole = 'inventory_manager';
  String _durationUnit = 'M';
  bool _busy = false;
  String? _notice;
  String? _token;

  @override
  void dispose() {
    _contact.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _isEmail => _contact.text.contains('@');

  Future<void> _check() async {
    final api = AppScope.of(context).api;
    final value = _contact.text.trim();
    if (value.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await api.gymLookupPerson(
        widget.gymId,
        phone: _isEmail ? null : value,
        email: _isEmail ? value : null,
        orgType: widget.orgType,
      );
      if (!mounted) return;
      setState(() {
        _notice = res['found'] == true
            ? context
                  .tr('invite.lookupFound')
                  .replaceAll('{name}', res['maskedName']?.toString() ?? '')
            : context.tr('invite.lookupNotFound');
      });
    } catch (e) {
      if (mounted) setState(() => _notice = inviteErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final api = AppScope.of(context).api;
    if (_contact.text.trim().isEmpty) {
      setState(() => _notice = context.tr('invite.errContact'));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await api.gymCreateInvitation(
        widget.gymId,
        buildInvitationBody(
          role: widget.role,
          contact: _contact.text,
          aclPermissions: _scopes.toList(),
          durationUnit: _durationUnit,
          paidAmount: num.tryParse(_amount.text.trim()),
          today: DateTime.now(),
          orgType: widget.orgType,
          vendorRole: _vendorRole,
          vendorPermissions: _vendorPerms.toList(),
        ),
        orgType: widget.orgType,
      );
      if (!mounted) return;
      final delivery = res['delivery'] is Map ? res['delivery'] as Map : null;
      setState(() {
        _token = res['token']?.toString();
        _notice = res['created'] == false
            ? context.tr('invite.alreadySent')
            // FitFlex told them itself (and gave someone new a start PIN).
            : delivery?['sent'] == true
            ? context.tr(
                delivery?['startPin'] == true
                    ? 'invite.sentWithPin'
                    : 'invite.sentNotice',
              )
            : context.tr('invite.sent');
      });
    } catch (e) {
      if (mounted) setState(() => _notice = inviteErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = _token != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FFTokens.spacingMd,
        0,
        FFTokens.spacingMd,
        MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingMd,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              // A shop's staff are not gym staff.
              widget.orgType == 'vendor' && widget.role == 'staff'
                  ? context.tr('vendor.invite.staffTitle')
                  : context
                        .tr('invite.sheetTitle')
                        .replaceAll(
                          '{role}',
                          inviteRoleLabel(context, widget.role),
                        ),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('invite.sheetBody'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            FFTextField(
              key: const Key('invite-contact'),
              controller: _contact,
              label: context.tr('invite.contact'),
              keyboardType: TextInputType.emailAddress,
              enabled: !sent,
              suffixIcon: IconButton(
                key: const Key('invite-check'),
                tooltip: context.tr('invite.check'),
                icon: const Icon(Icons.person_search_outlined),
                onPressed: _busy || sent ? null : _check,
              ),
            ),
            if (widget.orgType == 'vendor') ...[
              const SizedBox(height: FFTokens.spacingMd),
              DropdownButtonFormField<String>(
                key: const Key('invite-vendor-role'),
                initialValue: _vendorRole,
                decoration: InputDecoration(
                  labelText: context.tr('vendor.role'),
                ),
                items: [
                  for (final entry in _vendorRoles.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(context.tr(entry.value)),
                    ),
                ],
                onChanged: sent
                    ? null
                    : (v) => setState(() {
                        _vendorRole = v ?? _vendorRole;
                        // Q-15: the Sales role starts with `sales`.
                        if (_vendorRole == 'sales' && widget.vendorSales) {
                          _vendorPerms.add('sales');
                        }
                      }),
              ),
              // An admin holds every permission, so there is nothing to choose.
              if (_vendorRole != 'admin')
                for (final permission in [
                  ..._vendorPermissions.take(2),
                  if (widget.vendorSales) 'sales',
                  ..._vendorPermissions.skip(2),
                  if (widget.vendorPurchases) 'purchases',
                ])
                  CheckboxListTile(
                    key: Key('invite-vendor-permission-$permission'),
                    dense: true,
                    enabled: !sent,
                    value: _vendorPerms.contains(permission),
                    title: Text(context.tr('vendor.permission.$permission')),
                    onChanged: (on) => setState(
                      () => on == true
                          ? _vendorPerms.add(permission)
                          : _vendorPerms.remove(permission),
                    ),
                  ),
            ],
            if (widget.orgType == 'gym' && widget.role == 'staff') ...[
              const SizedBox(height: FFTokens.spacingMd),
              Text(context.tr('staff.permissions')),
              Wrap(
                spacing: 8,
                children: [
                  for (final scope in _staffScopes)
                    FilterChip(
                      key: Key('invite-scope-$scope'),
                      label: Text(_scopeLabel(context, scope)),
                      selected: _scopes.contains(scope),
                      onSelected: sent
                          ? null
                          : (on) => setState(
                              () => on
                                  ? _scopes.add(scope)
                                  : _scopes.remove(scope),
                            ),
                    ),
                ],
              ),
            ],
            if (widget.role == 'member') ...[
              const SizedBox(height: FFTokens.spacingMd),
              DropdownButtonFormField<String>(
                key: const Key('invite-duration'),
                initialValue: _durationUnit,
                decoration: InputDecoration(
                  labelText: context.tr('owner.durationUnit'),
                ),
                items: [
                  for (final unit in const ['D', 'W', 'M'])
                    DropdownMenuItem(
                      value: unit,
                      child: Text(context.tr('invite.duration$unit')),
                    ),
                ],
                onChanged: sent
                    ? null
                    : (v) => setState(() => _durationUnit = v ?? 'M'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('invite-amount'),
                controller: _amount,
                label: context.tr('owner.paidAmount'),
                helperText: context.tr('invite.paidHint'),
                keyboardType: TextInputType.number,
                enabled: !sent,
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: FFTokens.spacingMd),
              Text(_notice!, key: const Key('invite-notice')),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            if (!sent)
              FFButton(
                key: const Key('invite-send'),
                label: context.tr('invite.send'),
                onPressed: _busy ? null : _send,
              )
            else ...[
              FFButton(
                key: const Key('invite-copy-link'),
                label: context.tr('invite.copyLink'),
                onPressed: () async {
                  final messenger = FFSnack.of(context);
                  final copied = context.tr('invite.linkCopied');
                  await Clipboard.setData(
                    ClipboardData(text: inviteLink(_token!)),
                  );
                  messenger.success(copied);
                },
                variant: FFButtonVariant.secondary,
                icon: Icons.link,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFButton(
                key: const Key('invite-done'),
                label: context.tr('invite.done'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Organisation: invitations sent ──────────────────────────────────────────

/// Invitations a gym has sent, with the actions for a paid invitation that
/// expired before the person accepted.
class GymInvitationsPage extends StatefulWidget {
  const GymInvitationsPage({
    super.key,
    required this.gymId,
    this.orgType = 'gym',
  });

  /// The organisation's id: a gym, or with [orgType] 'vendor' the vendor.
  final String gymId;
  final String orgType;

  @override
  State<GymInvitationsPage> createState() => _GymInvitationsPageState();
}

class _GymInvitationsPageState extends State<GymInvitationsPage> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final res = await api.gymInvitations(
        widget.gymId,
        orgType: widget.orgType,
      );
      final raw = res['invitations'];
      if (!mounted) return;
      setState(() {
        _items = raw is List
            ? raw
                  .whereType<Map>()
                  .map((i) => Map<String, dynamic>.from(i))
                  .toList()
            : const [];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = inviteErrorMessage(context, e);
      });
    }
  }

  Future<void> _act(Map<String, dynamic> inv, String action) async {
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final done = context.tr('invite.actionDone');
    try {
      await api.gymInvitationAction(
        widget.gymId,
        inv['id'].toString(),
        action,
        orgType: widget.orgType,
      );
      messenger.success(done);
      await _load();
    } catch (e) {
      if (mounted) {
        messenger.error(inviteErrorMessage(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('invite.sentTitle'))),
      body: SafeArea(
        child: _loading
            ? const Center(child: FFSpinner(size: 32))
            : ListView(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                children: [
                  if (_error != null) Text(_error!),
                  if (_error == null && _items.isEmpty)
                    Text(
                      context.tr('invite.sentEmpty'),
                      textAlign: TextAlign.center,
                    ),
                  for (final inv in _items) _sentTile(context, inv),
                ],
              ),
      ),
    );
  }

  Widget _sentTile(BuildContext context, Map<String, dynamic> inv) {
    final open = inv['status'] == 'pending' || inv['status'] == 'claimed';
    final lapsedPaid = inv['needsResolution'] == true;
    final id = inv['id'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inv['identifierValue']?.toString() ?? '',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${inviteRoleLabel(context, inv['role'])} · '
              '${context.tr('invite.status.${inv['status']}')}',
            ),
            if (lapsedPaid)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context
                      .tr('invite.lapsedPaid')
                      .replaceAll(
                        '{amount}',
                        (inv['paidAmountTzs'] as num?)?.toStringAsFixed(0) ??
                            '',
                      ),
                  key: Key('lapsed-$id'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (open || lapsedPaid)
              Wrap(
                spacing: 8,
                children: [
                  if (open)
                    FFButton(
                      key: Key('resend-$id'),
                      label: context.tr('invite.resend'),
                      onPressed: () => _act(inv, 'resend'),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                  if (open)
                    FFButton(
                      key: Key('cancel-$id'),
                      label: context.tr('invite.cancel'),
                      onPressed: () => _act(inv, 'cancel'),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                  if (lapsedPaid)
                    FFButton(
                      key: Key('reissue-$id'),
                      label: context.tr('invite.reissue'),
                      onPressed: () => _act(inv, 'reissue'),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                  if (lapsedPaid)
                    FFButton(
                      key: Key('refunded-$id'),
                      label: context.tr('invite.markRefunded'),
                      onPressed: () => _act(inv, 'refunded'),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Owner profile entry to the gym's sent invitations (hidden while
/// invitations are off).
class GymInvitationsTile extends StatelessWidget {
  const GymInvitationsTile({super.key, required this.gymId});

  final String? gymId;

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final id = gymId;
        if (!auth.invitesEnabled || id == null) return const SizedBox.shrink();
        return FFActionTile(
          key: const Key('gym-invitations-tile'),
          icon: Icons.outgoing_mail,
          title: context.tr('invite.sentTitle'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GymInvitationsPage(gymId: id)),
          ),
        );
      },
    );
  }
}
