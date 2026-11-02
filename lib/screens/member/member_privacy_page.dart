import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/gym_sharing.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/shop_home/shop_personalisation.dart';
import 'member_shell.dart';
import 'widgets/phone_steps_card.dart';
import 'widgets/share_picker.dart' show SocialPrivacySection;

/// Settings → Privacy & data.
class MemberPrivacyPage extends StatelessWidget {
  const MemberPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final connections = MemberDataScope.of(
      context,
    ).trainerConnections.where((c) => c.status.isOpen).toList();
    final sharingWith = connections.where((c) => !c.permissions.isEmpty).length;
    final gyms = MemberDataScope.of(context).gymSharing;
    final gymsSharing = gyms.where((g) => g.permissions.isNotEmpty).length;
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        _BackRow(
          label: context.tr('member.profile'),
          to: AppRoutes.memberProfile,
        ),
        FFPageHeader(
          title: context.tr('privacy.title'),
          description: context.tr('privacy.body'),
        ),
        // Events S7 (spec §5.2): said where the member reads about their
        // data, only while the server counts screen use.
        if (MemberDataScope.of(context).eventsOptions.analytics.enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
            child: Text(
              context.tr('events.privacy.analytics'),
              key: const Key('privacy-events-analytics'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        FFActionTile(
          key: const Key('privacy-messages'),
          icon: Icons.mark_email_unread_outlined,
          title: context.tr('msgPrefs.title'),
          subtitle: context.tr('msgPrefs.tile'),
          onTap: () => context.push(AppRoutes.memberMessageSettings),
        ),
        // Shop Phase 2 S2: hidden unless SHOP_PERSONALISATION is on.
        const ShopPrivacyTile(),
        FFActionTile(
          key: const Key('privacy-activity-sharing'),
          icon: Icons.share_outlined,
          title: context.tr('sharing.title'),
          subtitle: [
            connections.isEmpty
                ? context.tr('sharing.noTrainers')
                : context
                      .tr('sharing.summary')
                      .replaceAll('{n}', '$sharingWith')
                      .replaceAll('{total}', '${connections.length}'),
            if (gyms.isNotEmpty)
              context
                  .tr('gymShare.summary')
                  .replaceAll('{n}', '$gymsSharing')
                  .replaceAll('{total}', '${gyms.length}'),
          ].join(' · '),
          onTap: () => context.go(AppRoutes.memberActivitySharing),
        ),
        const PhoneStepsSwitch(),
        const SocialPrivacySection(),
      ],
    );
  }
}

/// Settings → Privacy & data → Activity sharing: per trainer, exactly what
/// they can see. Every switch saves straight away and applies to the
/// trainer's next view; access can be stopped entirely or the connection
/// ended.
class MemberActivitySharingPage extends StatefulWidget {
  const MemberActivitySharingPage({super.key});

  @override
  State<MemberActivitySharingPage> createState() =>
      _MemberActivitySharingPageState();
}

/// The rows members see. "Activity data" covers steps, distance and active
/// minutes together, and can be expanded to set them one by one.
const _activityGroup = [
  TrainerPermission.steps,
  TrainerPermission.distance,
  TrainerPermission.activeMinutes,
];
const _otherRows = [
  TrainerPermission.workoutHistory,
  TrainerPermission.workoutDetails,
  TrainerPermission.goals,
  TrainerPermission.streaks,
  TrainerPermission.challenges,
];

class _MemberActivitySharingPageState extends State<MemberActivitySharingPage> {
  /// Connection id → permissions being saved (shown optimistically).
  final Map<String, TrainerPermissions> _pending = {};
  final Set<String> _saving = {};
  final Set<String> _expanded = {};
  final Set<String> _saved = {};

  MemberShellState? get _shell =>
      context.findAncestorStateOfType<MemberShellState>();

  TrainerPermissions _current(TrainerConnection c) =>
      _pending[c.id] ?? c.permissions;

  Future<void> _apply(TrainerConnection c, TrainerPermissions next) async {
    final api = AppScope.of(context).api;
    final data = MemberDataScope.of(context);
    final messenger = FFSnack.of(context);
    final failed = context.tr('sharing.failed');
    setState(() {
      _pending[c.id] = next;
      _saving.add(c.id);
      _saved.remove(c.id);
    });
    try {
      await api.updateTrainerConnection(c.id, next.toJson());
      // Reflect the change everywhere without waiting for a refresh.
      data.update(
        (d) => d.trainerConnections = [
          for (final x in d.trainerConnections)
            x.id == c.id ? x.withPermissions(next) : x,
        ],
      );
      if (mounted) setState(() => _saved.add(c.id));
    } catch (_) {
      messenger.error(failed);
    } finally {
      if (mounted) {
        setState(() {
          _pending.remove(c.id);
          _saving.remove(c.id);
        });
      }
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showFFConfirmDialog(
        context,
        title: title,
        message: body,
        cancelLabel: context.tr('workout.keepGoing'),
        confirmLabel: action,
        confirmKey: const Key('sharing-confirm'),
      ) ==
      true;

  Future<void> _stopAll(TrainerConnection c, String name) async {
    final ok = await _confirm(
      context.tr('sharing.stopTitle'),
      context.tr('sharing.stopBody').replaceAll('{name}', name),
      context.tr('sharing.stop'),
    );
    if (ok && mounted) await _apply(c, const TrainerPermissions());
  }

  Future<void> _disconnect(TrainerConnection c, String name) async {
    final pending = c.status == TrainerConnectionStatus.pending;
    final ok = await _confirm(
      context.tr(pending ? 'connect.cancelTitle' : 'connect.endTitle'),
      context
          .tr(pending ? 'connect.cancelBody' : 'connect.endBody')
          .replaceAll('{name}', name),
      context.tr(pending ? 'connect.cancel' : 'connect.end'),
    );
    if (!ok || !mounted) return;
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final failed = context.tr('sharing.failed');
    setState(() => _saving.add(c.id));
    try {
      await api.endTrainerConnection(c.id);
      await _shell?.refreshConnections();
    } catch (_) {
      messenger.error(failed);
    } finally {
      if (mounted) setState(() => _saving.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections = MemberDataScope.of(
      context,
    ).trainerConnections.where((c) => c.status.isOpen).toList();
    return ListView(
      key: const Key('activity-sharing'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        _BackRow(
          label: context.tr('privacy.title'),
          to: AppRoutes.memberPrivacy,
        ),
        FFPageHeader(
          title: context.tr('sharing.title'),
          description: context.tr('sharing.body'),
        ),
        FFSectionTitle(context.tr('sharing.trainers')),
        if (connections.isEmpty)
          FFEmptyState(
            title: context.tr('sharing.noTrainers'),
            body: context.tr('connect.noneBody'),
            action: FFButton(
              label: context.tr('member.findTrainer'),
              onPressed: () => context.go(AppRoutes.memberTrainers),
              variant: FFButtonVariant.secondary,
            ),
          )
        else
          for (final c in connections) _trainerCard(context, c),
        const GymSharingSection(),
      ],
    );
  }

  Widget _trainerCard(BuildContext context, TrainerConnection c) {
    final theme = Theme.of(context);
    final name = c.trainer?.displayName ?? context.tr('connect.yourTrainer');
    final perms = _current(c);
    final busy = _saving.contains(c.id);
    final grouped = _activityGroup.where(perms.has).length;
    final expanded = _expanded.contains(c.id);

    Widget row(
      String key,
      String label,
      String hint,
      bool? value,
      ValueChanged<bool> onChanged, {
      bool indent = false,
    }) => Padding(
      padding: EdgeInsets.only(left: indent ? FFTokens.spacingLg : 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                Text(hint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // A partly-on group shows as a dash; tapping turns it all on.
          value == null
              ? IconButton(
                  key: Key('sharing-$key-${c.id}'),
                  tooltip: context.tr('sharing.partial'),
                  onPressed: busy ? null : () => onChanged(true),
                  icon: const Icon(Icons.remove_circle_outline),
                )
              : Switch(
                  key: Key('sharing-$key-${c.id}'),
                  value: value,
                  onChanged: busy ? null : onChanged,
                ),
        ],
      ),
    );

    return FFCard(
      key: Key('sharing-card-${c.id}'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FFAvatar(name: name, src: c.trainer?.photoUrl),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('sharing.trainerLabel').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.6,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (c.status == TrainerConnectionStatus.pending)
                FFPill(label: context.tr('connect.status.pending')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
            child: Text(
              key: Key('sharing-status-${c.id}'),
              busy
                  ? context.tr('sharing.saving')
                  : _saved.contains(c.id)
                  ? context.tr('sharing.savedNow').replaceAll('{name}', name)
                  : c.status == TrainerConnectionStatus.pending
                  ? context.tr('sharing.pendingNote')
                  : context.tr('sharing.liveNote').replaceAll('{name}', name),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _saved.contains(c.id) && !busy
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),
          ),
          row(
            'activity',
            context.tr('sharing.activityData'),
            context.tr('sharing.activityData.hint'),
            grouped == 0
                ? false
                : grouped == _activityGroup.length
                ? true
                : null,
            (on) {
              var next = perms;
              for (final p in _activityGroup) {
                next = next.toggle(p, on);
              }
              _apply(c, next);
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FFButton(
              key: Key('sharing-activity-expand-${c.id}'),
              label: context.tr(expanded ? 'sharing.fewer' : 'sharing.choose'),
              onPressed: () => setState(
                () => expanded ? _expanded.remove(c.id) : _expanded.add(c.id),
              ),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
            ),
          ),
          if (expanded)
            for (final p in _activityGroup)
              row(
                p.wire,
                context.tr('share.${p.wire}'),
                context.tr('share.${p.wire}.hint'),
                perms.has(p),
                (on) => _apply(c, perms.toggle(p, on)),
                indent: true,
              ),
          for (final p in _otherRows) ...[
            const Divider(height: FFTokens.spacingLg),
            row(
              p.wire,
              context.tr(
                p == TrainerPermission.challenges
                    ? 'sharing.challengeData'
                    : 'share.${p.wire}',
              ),
              context.tr('share.${p.wire}.hint'),
              perms.has(p),
              (on) => _apply(c, perms.toggle(p, on)),
            ),
          ],
          const SizedBox(height: FFTokens.spacingSm),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              if (!perms.isEmpty)
                FFButton(
                  key: Key('sharing-stop-${c.id}'),
                  label: context.tr('sharing.stop'),
                  onPressed: busy ? null : () => _stopAll(c, name),
                  variant: FFButtonVariant.secondary,
                ),
              TextButton(
                key: Key('sharing-disconnect-${c.id}'),
                onPressed: busy ? null : () => _disconnect(c, name),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: Text(
                  context.tr(
                    c.status == TrainerConnectionStatus.pending
                        ? 'connect.cancel'
                        : 'connect.end',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.label, required this.to});

  final String label;
  final String to;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FFButton(
      label: label,
      // Opened on top of another screen (the shop's Why sheet pushes the
      // Privacy page): Back returns there. Otherwise go to [to].
      onPressed: () => context.canPop() ? context.pop() : context.go(to),
      variant: FFButtonVariant.ghost,
      size: FFButtonSize.sm,
      icon: Icons.arrow_back,
    ),
  );
}

/// Activity sharing → Gyms: check-ins and visit patterns are always the
/// gym's; the extra items start on and can be switched off here.
class GymSharingSection extends StatefulWidget {
  const GymSharingSection({super.key});

  @override
  State<GymSharingSection> createState() => _GymSharingSectionState();
}

class _GymSharingSectionState extends State<GymSharingSection> {
  final Map<String, Set<GymPermission>> _pending = {};
  final Set<String> _saved = {};

  Future<void> _set(GymSharing g, GymPermission p, bool on) async {
    final api = AppScope.of(context).api;
    final data = MemberDataScope.of(context);
    final messenger = FFSnack.of(context);
    final failed = context.tr('sharing.failed');
    final next = {...g.permissions};
    on ? next.add(p) : next.remove(p);
    setState(() {
      _pending[g.gym.id] = next;
      _saved.remove(g.gym.id);
    });
    try {
      await api.updateGymSharing(g.gym.id, gymPermissionsJson(next));
      data.update(
        (d) => d.gymSharing = [
          for (final x in d.gymSharing)
            x.gym.id == g.gym.id ? x.withPermissions(next) : x,
        ],
      );
      if (mounted) setState(() => _saved.add(g.gym.id));
    } catch (_) {
      messenger.error(failed);
    } finally {
      if (mounted) setState(() => _pending.remove(g.gym.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gyms = MemberDataScope.of(context).gymSharing;
    return Column(
      key: const Key('gym-sharing'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('gymShare.title')),
        if (gyms.isEmpty)
          FFEmptyState(
            title: context.tr('gymShare.none'),
            body: context.tr('gymShare.noneBody'),
          )
        else
          for (final g in gyms)
            FFCard(
              key: Key('gym-sharing-${g.gym.id}'),
              margin: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.gym.name ?? '',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    context.tr(
                      g.reasons.contains('member')
                          ? 'gymShare.yourGym'
                          : 'gymShare.visited',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  // Not a switch: the gym records these itself.
                  Row(
                    key: Key('gym-always-${g.gym.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline, size: 18),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Text(
                          context
                              .tr('gymShare.always')
                              .replaceAll('{gym}', g.gym.name ?? ''),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  for (final p in GymPermission.values) ...[
                    const Divider(height: FFTokens.spacingLg),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('gymShare.${p.wire}'),
                                style: theme.textTheme.bodyLarge,
                              ),
                              Text(
                                context.tr('gymShare.${p.wire}.hint'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          key: Key('gym-share-${p.wire}-${g.gym.id}'),
                          value: (_pending[g.gym.id] ?? g.permissions).contains(
                            p,
                          ),
                          onChanged: _pending.containsKey(g.gym.id)
                              ? null
                              : (on) => _set(g, p, on),
                        ),
                      ],
                    ),
                  ],
                  if (_saved.contains(g.gym.id))
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                      child: Text(
                        context
                            .tr('sharing.savedNow')
                            .replaceAll('{name}', g.gym.name ?? ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            context.tr('gymShare.neverShared'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
