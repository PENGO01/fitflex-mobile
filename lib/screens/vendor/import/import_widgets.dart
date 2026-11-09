// Vendor smart import V3: pieces the three import screens share, built from
// the shared FF* components. Wording comes from i18n (`vendor.import.*`) or
// from the server's own {en, sw} messages; a raw code is never shown.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../documents/document_share_sheet.dart' show DocumentActions;
import 'import_models.dart';

String importLang(BuildContext context) =>
    FFLocaleScope.of(context).locale.languageCode;

String importEntityLabel(BuildContext context, ImportEntity? e) => context.tr(
  e == null ? 'vendor.import.entity.unknown' : 'vendor.import.entity.${e.name}',
);

String importStatusLabel(BuildContext context, BatchStatus s) =>
    context.tr('vendor.import.status.${s.wire}');

FFBadgeTone importStatusTone(BatchStatus s) => switch (s) {
  BatchStatus.applied => FFBadgeTone.success,
  BatchStatus.partial || BatchStatus.mappingRequired => FFBadgeTone.warning,
  BatchStatus.applying => FFBadgeTone.brand,
  BatchStatus.discarded => FFBadgeTone.gray,
  _ => FFBadgeTone.info,
};

/// "Ready to import" etc. as a badge that may wrap in Swahili.
class ImportStatusBadge extends StatelessWidget {
  const ImportStatusBadge({super.key, required this.status});
  final BatchStatus status;

  @override
  Widget build(BuildContext context) => FFBadge(
    label: importStatusLabel(context, status),
    tone: importStatusTone(status),
    wrap: true,
  );
}

/// Numbers in a two-column grid that follows the width (320 to wide).
class ImportCountsGrid extends StatelessWidget {
  const ImportCountsGrid({super.key, required this.items, this.keyPrefix});

  /// (label, value) in order.
  final List<(String, int)> items;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = FFTokens.spacingSm;
        final w = box.maxWidth.isFinite ? (box.maxWidth - gap) / 2 : 150.0;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, (label, value)) in items.indexed)
              SizedBox(
                width: w,
                child: FFCard(
                  key: keyPrefix == null ? null : Key('$keyPrefix-$i'),
                  margin: EdgeInsets.zero,
                  child: Semantics(
                    container: true,
                    label: '$label: $value',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$value', style: theme.textTheme.titleLarge),
                        Text(label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One checked row: its number and name, status, the server's messages for
/// its issues, and why it did not apply.
class ImportRowTile extends StatelessWidget {
  const ImportRowTile({super.key, required this.row});
  final ImportRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tr;
    final lang = importLang(context);
    final label = row.label;
    final messages = <String>[
      for (final i in row.issues)
        if (i.severity != 'info')
          i.message?.of(lang) ?? t('vendor.import.issue.generic'),
    ];
    final failedText = row.failed
        ? (row.lastErrorMessage?.of(lang) ?? t('vendor.import.rowError'))
        : null;
    final (badge, tone) = row.failed
        ? (t('vendor.import.rowStatus.failed'), FFBadgeTone.danger)
        : switch (row.status) {
            'invalid' => (
              t('vendor.import.rowStatus.invalid'),
              FFBadgeTone.danger,
            ),
            'needs_review' => (
              t('vendor.import.rowStatus.needs_review'),
              FFBadgeTone.warning,
            ),
            _ => (t('vendor.import.rowStatus.valid'), FFBadgeTone.success),
          };
    final title = t('vendor.import.rowNo').replaceAll('{n}', '${row.rowNo}');
    final all = [?failedText, ...messages];
    return FFCard(
      key: Key('import-row-${row.id}'),
      child: Semantics(
        container: true,
        label: [title, ?label, badge, ...all].join('. '),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                FFBadge(label: badge, tone: tone, wrap: true),
              ],
            ),
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
            for (final m in all)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(m, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hands a CSV to the person: Flutter web downloads it, a phone opens the
/// share sheet. Tests replace [DocumentActions].
Future<void> deliverImportCsv(Uint8List bytes, String fileName) async {
  const mime = 'text/csv';
  if (DocumentActions.isWeb()) {
    await DocumentActions.download(bytes, fileName, mime);
  } else {
    await DocumentActions.shareTypedFile(bytes, fileName, mime);
  }
}

/// A full-width, 48dp-tall button at every width; long Swahili labels wrap
/// onto up to three lines. The key sits on the FFButton itself.
Widget importButton({
  Key? key,
  required String label,
  required VoidCallback? onPressed,
  FFButtonVariant variant = FFButtonVariant.primary,
  IconData? icon,
  bool loading = false,
}) => FFButton(
  key: key,
  label: label,
  onPressed: onPressed,
  variant: variant,
  icon: icon,
  loading: loading,
  fullWidth: true,
  maxLines: 3,
  visualDensity: VisualDensity.standard,
);

const _knownFields = {
  'name', 'price_tzs', 'stock', 'category', 'description', 'brand', 'sku', //
  'discount_price_tzs', 'cost_tzs', 'reorder_level', 'image', 'quantity',
  'variant', 'businessName', 'businessCategory', 'contactNumber', 'email',
  'address', 'businessHours',
};

/// The label of a field the server matched a column to; an unknown field is
/// named neutrally, never by its raw key.
String importFieldLabel(BuildContext context, String field) => context.tr(
  _knownFields.contains(field)
      ? 'vendor.import.field.$field'
      : 'vendor.import.field.other',
);
