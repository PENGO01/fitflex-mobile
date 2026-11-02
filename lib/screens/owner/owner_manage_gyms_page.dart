import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/gym_form_page.dart';
import '../../shared/widgets/payout_owner_marker.dart';
import 'owner_shell.dart';
import '../member/widgets/gym_filters.dart';

/// Owner — manage gyms grid view with add / edit / delete.
class OwnerManageGymsPage extends StatelessWidget {
  const OwnerManageGymsPage({super.key});

  int _crossAxisCount(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final ownerGymList = data.ownerGyms;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _crossAxisCount(constraints.maxWidth);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  0,
                ),
                child: Text(
                  context.tr('owner.gymProfile'),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            if (ownerGymList.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: FFEmptyState(title: context.tr('member.noData')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                // Rows of cards rather than a fixed-ratio grid: each row is as
                // tall as its tallest card, so long names, Swahili pills and
                // large text grow the card instead of overflowing it.
                sliver: SliverList.separated(
                  itemCount: (ownerGymList.length + cols - 1) ~/ cols,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: FFTokens.spacingMd),
                  itemBuilder: (ctx, row) => IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < cols; col++) ...[
                          if (col > 0)
                            const SizedBox(width: FFTokens.spacingMd),
                          Expanded(
                            child: _gridCell(
                              context,
                              ownerGymList,
                              row * cols + col,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  ownerGymList.isEmpty ? 0 : 0,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                ),
                child: FFButton(
                  label: context.tr('owner.addGym'),
                  onPressed: () => _showAddGymDialog(context),
                  variant: FFButtonVariant.secondary,
                  icon: Icons.add,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _gridCell(
    BuildContext context,
    List<Map<String, dynamic>> gyms,
    int i,
  ) {
    if (i >= gyms.length) return const SizedBox.shrink();
    return _OwnerGymGridCard(
      gym: gyms[i],
      onEdit: () => _showEditGymDialog(context, gyms[i]),
      onDelete: () => _confirmDeleteGym(context, gyms[i]),
    );
  }

  Future<void> _showAddGymDialog(BuildContext context) async {
    final payload = await openGymForm(context);
    if (payload == null) return;
    if (!context.mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.gymAdded');
    try {
      await api.ownerCreateGym(payload);
      if (!context.mounted) return;
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      FFSnack.error(context, apiErrorMessage(FFLocaleScope.of(context), e));
    }
  }

  Future<void> _showEditGymDialog(
    BuildContext context,
    Map<String, dynamic> gym,
  ) async {
    final payload = await openGymForm(context, initial: gym);
    if (payload == null) return;
    if (!context.mounted) return;
    final api = AppScope.of(context).api;
    final message = context.tr('owner.gymUpdated');
    try {
      await api.ownerUpdateGym(gym['id'].toString(), payload);
      if (!context.mounted) return;
      final shell = context.findAncestorStateOfType<OwnerShellState>();
      await shell?.refreshAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      FFSnack.error(context, apiErrorMessage(FFLocaleScope.of(context), e));
    }
  }

  void _confirmDeleteGym(BuildContext context, Map<String, dynamic> gym) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('owner.deleteGym')),
        content: Text(context.tr('owner.confirmDelete')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final api = AppScope.of(context).api;
              final message = context.tr('owner.gymDeleted');
              try {
                await api.ownerDeleteGym(gym['id'].toString());
                if (!context.mounted) return;
                final shell = context
                    .findAncestorStateOfType<OwnerShellState>();
                await shell?.refreshAll();
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } on ApiException catch (e) {
                if (!context.mounted) return;
                FFSnack.error(
                  context,
                  apiErrorMessage(FFLocaleScope.of(context), e),
                );
              }
            },
            child: Text(context.tr('owner.deleteGym')),
          ),
        ],
      ),
    );
  }
}

class _OwnerGymGridCard extends StatelessWidget {
  const _OwnerGymGridCard({
    required this.gym,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> gym;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static Widget _cover(ColorScheme cs, String? src) {
    final placeholder = Container(
      color: cs.primary.withValues(alpha: 0.1),
      child: Icon(Icons.fitness_center, size: 36, color: cs.primary),
    );
    if (src == null) return placeholder;
    return FFRemoteImage(
      src: src,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      fallback: placeholder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final images = (gym['images'] as List?)?.whereType<String>().toList() ?? [];
    final thumbnails =
        (gym['thumbnails'] as List?)?.whereType<String>().toList() ?? [];
    final coverThumbnail = thumbnails.isNotEmpty
        ? thumbnails.first
        : (images.isNotEmpty ? images.first : null);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(FFTokens.radiusLg),
            ),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cover(cs, coverThumbnail),
                  // On the photo, so a narrow card keeps its height.
                  if (isPayoutOwnerGym(gym))
                    PositionedDirectional(
                      top: FFTokens.spacingSm,
                      start: FFTokens.spacingSm,
                      end: FFTokens.spacingSm,
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: PayoutOwnerMarker(
                          key: Key('owner-gym-payout-owner-${gym['id']}'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(FFTokens.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: FFTokens.spacing2xs),
                  Text(
                    gym['location']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Wrap(
                    spacing: FFTokens.spacingXs,
                    runSpacing: FFTokens.spacingXs,
                    children: [
                      FFPill(label: tierLabel(context, tierKeyOf(gym['tier']))),
                      FFPill(
                        label:
                            gym['status']?.toString() ??
                            context.tr('ownerReg.status_active'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          // Wraps rather than overflowing if the card is ever too narrow.
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              IconButton(
                key: Key('owner-gym-entrance-qr-${gym['id']}'),
                icon: const Icon(Icons.qr_code_2, size: FFTokens.iconMd),
                onPressed: () => showGymEntranceQr(
                  context,
                  gymId: gym['id']?.toString() ?? '',
                  gymName: gym['name']?.toString() ?? '',
                ),
                tooltip: context.tr('owner.entranceQr'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: FFTokens.iconMd),
                onPressed: onEdit,
                tooltip: context.tr('owner.editGym'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: FFTokens.iconMd,
                  color: cs.error,
                ),
                onPressed: onDelete,
                tooltip: context.tr('owner.deleteGym'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tech Brief §5: the static QR members scan to check themselves in.
Future<void> showGymEntranceQr(
  BuildContext context, {
  required String gymId,
  required String gymName,
}) async {
  final api = AppScope.of(context).api;
  final locale = FFLocaleScope.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(gymName),
      content: FutureBuilder<Map<String, dynamic>>(
        future: api.gymEntranceQr(gymId),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return FFAlert(
              tone: FFAlertTone.error,
              message: errorMessage(locale, snap.error!),
            );
          }
          final payload = snap.data?['payload']?.toString();
          if (payload == null) {
            return const SizedBox(
              height: 240,
              child: Center(child: FFSpinner(size: 32)),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 240,
                height: 240,
                child: FFQrCode(
                  key: const Key('owner-entrance-qr-image'),
                  data: payload,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ctx.tr('owner.entranceQrHint'),
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.tr('member.close')),
        ),
      ],
    ),
  );
}
