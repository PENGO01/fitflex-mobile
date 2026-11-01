import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app_scope.dart';
import '../../../../shared/api_client.dart' show ApiException;
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_medal.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/i18n.dart';

/// The stage chip of a result: always a word (never colour alone), with a
/// tone that matches how official the result is (spec §10.3, §10.6).
class ResultStageChip extends StatelessWidget {
  const ResultStageChip({super.key, required this.stage});

  final ResultStage stage;

  @override
  Widget build(BuildContext context) {
    final tone = switch (stage) {
      ResultStage.official => FFBadgeTone.success,
      ResultStage.corrected => FFBadgeTone.brand,
      ResultStage.provisional => FFBadgeTone.warning,
      ResultStage.disputed => FFBadgeTone.warning,
      ResultStage.disqualified || ResultStage.rejected => FFBadgeTone.danger,
      ResultStage.none => FFBadgeTone.gray,
    };
    return FFBadge(
      label: context.tr(stage.chipKey),
      tone: tone,
      dot: true,
      wrap: true,
    );
  }
}

/// A finish time read out in words for a screen reader ("1 hr 52 min 8
/// sec"), from the same parts the big number is drawn from.
String spokenResultTime(BuildContext context, int ms) {
  final p = resultTimeParts(ms);
  final key = p.h > 0
      ? 'events.duration.spoken.hms'
      : 'events.duration.spoken.ms';
  return context
      .tr(key)
      .replaceFirst('{h}', '${p.h}')
      .replaceFirst('{m}', '${p.m}')
      .replaceFirst('{s}', '${p.s}');
}

/// The `{reason}` words for a server reason code (`result_corrected`…), or
/// an empty string for none. Unknown codes read as no reason, never a raw
/// code.
String medalReasonWords(BuildContext context, String? code) {
  if (code == null || code.isEmpty) return '';
  const known = {
    'result_corrected',
    'disqualified',
    'registration_cancelled',
    'event_cancelled',
    'rule_changed_by_admin',
    'source_revoked',
  };
  return known.contains(code) ? context.tr('events.reason.$code') : '';
}

/// The reason clause for a result code (what follows "because"), or an
/// empty string for none. The codes are the backend's closed list
/// (reject, correct, disqualify and unlink); an unknown code reads as no
/// reason, never a raw code.
const resultReasonCodes = {
  'not_a_valid_run',
  'data_error',
  'duplicate',
  'timing_error',
  'wrong_bib',
  'late_finish_data',
  'rule_violation',
  'course_cut',
  'equipment',
  'identity',
  'virtual_evidence',
  'wrong_category',
  'other',
  'replaced_by_participant',
};

String resultReasonWords(BuildContext context, String? code) {
  if (code == null || code.isEmpty) return '';
  return resultReasonCodes.contains(code)
      ? context.tr('events.result.reason.$code')
      : '';
}

/// A sentence with its "because" clause only when there is a reason:
/// [plainKey] alone, or [becauseKey] with `{reason}` filled in.
String sentenceWithReason(
  BuildContext context, {
  required String plainKey,
  required String becauseKey,
  required String reason,
}) => reason.isEmpty
    ? context.tr(plainKey)
    : context.tr(becauseKey).replaceFirst('{reason}', reason);

/// A saved-copy key for this member (security review M7): the signed-in
/// user's id is part of it, so one member's copy is never read for another.
String memberCacheKey(BuildContext context, String base) {
  final uid = AppScope.of(context).auth.user?['id']?.toString() ?? '';
  return '$base.$uid';
}

/// A wallet answer without perk codes: a code is shown while the app is
/// open and is never written to the phone.
Map<String, dynamic> walletWithoutCodes(Map<String, dynamic> json) {
  final out = Map<String, dynamic>.from(json);
  final reds = out['redemptions'];
  if (reds is List) {
    out['redemptions'] = [
      for (final r in reds)
        if (r is Map) (Map<String, dynamic>.from(r)..remove('code')) else r,
    ];
  }
  return out;
}

/// Joins the non-empty parts of a screen-reader label with commas.
String tidyLabel(Iterable<String> parts) =>
    parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(', ');

/// What a screen reader says for a medal: name, event, category, then
/// "awarded {date}" or "removed {date}"; empty parts are skipped. A custom
/// description from the organizer replaces the name but never the event.
String medalSemanticsLabel(
  BuildContext context,
  MedalAward a,
  String lang, {
  required String dateText,
}) {
  final alt = a.art.altText.of(lang).trim();
  final dateKey = a.isRevoked
      ? 'events.medals.removedOn'
      : 'events.medals.awardedOn';
  final when = dateText.isEmpty
      ? ''
      : context.tr(dateKey).replaceFirst('{date}', dateText);
  return tidyLabel([
    alt.isEmpty ? a.name.of(lang) : alt,
    a.eventTitle,
    a.categoryName ?? '',
    when,
  ]);
}

// ── Medal artwork ────────────────────────────────────────────────────────

/// How medal pictures are fetched. Tests replace [fetch]; the app uses the
/// member's sign-in (`GET /events/medal-art/:id/file`), never a remote URL.
class MedalArtLoader {
  MedalArtLoader._();

  static final Map<String, Uint8List> _bytes = {};
  static final Set<String> _gone = {};
  static _ResumeObserver? _observer;

  static Future<Uint8List> Function(
    BuildContext context,
    String artId,
    String variant,
  )?
  fetch;

  /// Forget everything (tests, sign-out, app resume).
  static void reset() {
    _bytes.clear();
    _gone.clear();
  }

  /// Drops every size of one picture (taken down, or a 404).
  static void evict(String artId) =>
      _bytes.removeWhere((k, _) => k.startsWith('$artId/'));

  /// Pictures are not kept for the life of the app: a take-down shows up
  /// the next time the app is opened, and sign-out clears them (L6).
  static void _watch() {
    if (_observer != null) return;
    _observer = _ResumeObserver();
    WidgetsBinding.instance.addObserver(_observer!);
    EventsCache.clearHooks.add(reset);
  }

  /// The picture, or null when it is gone (taken down, not yours, offline
  /// and never saved): the caller draws the built-in design.
  static Future<Uint8List?> load(
    BuildContext context,
    String artId,
    String variant,
  ) async {
    _watch();
    final key = '$artId/$variant';
    final hit = _bytes[key];
    if (hit != null) return hit;
    if (_gone.contains(artId)) return null;
    try {
      final bytes = await (fetch != null
          ? fetch!(context, artId, variant)
          : AppScope.of(
              context,
            ).api.eventMedalArtFile(artId, variant: variant));
      if (bytes.isEmpty) return null;
      if (_bytes.length > 30) _bytes.remove(_bytes.keys.first);
      _bytes[key] = bytes;
      return bytes;
    } catch (e) {
      // A 404 is final for this id (ids are never reused); a network error
      // is retried next time.
      if (e is ApiException && e.status == 404) {
        _gone.add(artId);
        evict(artId);
      }
      return null;
    }
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) MedalArtLoader.reset();
  }
}

/// A medal in a circle: the organizer's own design when it can be shown,
/// else the built-in FitFlex design from the same award. Never blank.
class MedalBadge extends StatefulWidget {
  const MedalBadge({
    super.key,
    required this.art,
    this.size = 96,
    this.variant = 'm256',
    this.dimmed = false,
  });

  final MedalArt art;
  final double size;

  /// `m256` in grids, `m512` in the detail view.
  final String variant;
  final bool dimmed;

  @override
  State<MedalBadge> createState() => _MedalBadgeState();
}

class _MedalBadgeState extends State<MedalBadge> {
  Uint8List? _bytes;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(MedalBadge old) {
    super.didUpdateWidget(old);
    if (old.art.artId != widget.art.artId ||
        old.art.revision != widget.art.revision ||
        old.variant != widget.variant) {
      _bytes = null;
      _loadedFor = null;
      _maybeLoad();
    }
  }

  Future<void> _maybeLoad() async {
    final art = widget.art;
    if (!art.isCustom) return;
    final tag = '${art.artId}/${art.revision}/${widget.variant}';
    if (_loadedFor == tag) return;
    _loadedFor = tag;
    final bytes = await MedalArtLoader.load(
      context,
      art.artId!,
      widget.variant,
    );
    if (!mounted || _loadedFor != tag) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final fallback = BuiltinMedalArt(artKey: widget.art.safeArtKey, size: size);
    final Widget child = _bytes == null
        ? fallback
        : ClipOval(
            child: Image.memory(
              _bytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              // Bytes that don't decode never leave a hole.
              errorBuilder: (_, _, _) => fallback,
            ),
          );
    return ExcludeSemantics(
      child: Opacity(
        opacity: widget.dimmed ? 0.45 : 1,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}

/// The eight built-in designs (spec §7.7), drawn in code so they scale
/// without image files.
class BuiltinMedalArt extends StatelessWidget {
  const BuiltinMedalArt({super.key, required this.artKey, this.size = 96});

  final String artKey;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MedalPainter(artKey));
}

class _MedalPainter extends CustomPainter {
  _MedalPainter(this.artKey);

  final String artKey;

  ({Color ring, Color face, Color mark, bool star}) get _look =>
      switch (artKey) {
        'finisher_gold' => (
          ring: const Color(0xFFB7791F),
          face: const Color(0xFFF6C945),
          mark: const Color(0xFF7A4B00),
          star: true,
        ),
        'podium_gold' => (
          ring: const Color(0xFFB7791F),
          face: const Color(0xFFFFD54A),
          mark: const Color(0xFF6B4300),
          star: false,
        ),
        'podium_silver' => (
          ring: const Color(0xFF7B8794),
          face: const Color(0xFFD9DEE5),
          mark: const Color(0xFF3E4A59),
          star: false,
        ),
        'podium_bronze' => (
          ring: const Color(0xFF8A4B20),
          face: const Color(0xFFD99058),
          mark: const Color(0xFF52280C),
          star: false,
        ),
        'time_blue' => (
          ring: const Color(0xFF1B4F9C),
          face: const Color(0xFF5FA2F0),
          mark: const Color(0xFF0B2A57),
          star: true,
        ),
        'charity_red' => (
          ring: const Color(0xFF9B1C1C),
          face: const Color(0xFFEF6A6A),
          mark: const Color(0xFF560C0C),
          star: true,
        ),
        'virtual_teal' => (
          ring: const Color(0xFF0F766E),
          face: const Color(0xFF4FD1C5),
          mark: const Color(0xFF053F3A),
          star: true,
        ),
        _ => (
          ring: FFTokens.brand600,
          face: FFTokens.brand400,
          mark: FFTokens.brand800,
          star: true,
        ),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final look = _look;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = look.ring);
    canvas.drawCircle(c, r * 0.86, Paint()..color = look.face);
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = look.mark.withValues(alpha: 0.55),
    );
    final mark = Paint()..color = look.mark;
    if (look.star) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final rad = i.isEven ? r * 0.42 : r * 0.18;
        final a = -math.pi / 2 + i * math.pi / 5;
        final p = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, mark);
    } else {
      // A podium: three blocks, the middle one tallest.
      final w = r * 0.28;
      final base = c.dy + r * 0.3;
      for (final (i, h) in [(-1, 0.38), (0, 0.6), (1, 0.28)]) {
        final left = c.dx + i * w * 1.1 - w / 2;
        canvas.drawRect(Rect.fromLTWH(left, base - r * h, w, r * h), mark);
      }
    }
  }

  @override
  bool shouldRepaint(_MedalPainter old) => old.artKey != artKey;
}

// ── Cards that are shared as pictures ────────────────────────────────────

/// What leaves the app: a picture made on this phone (spec §7.7). Tests
/// replace [shareImage].
class EventShareActions {
  EventShareActions._();

  static Future<void> Function(Uint8List png, String fileName) shareImage =
      (png, fileName) async {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
            fileNameOverrides: [fileName],
          ),
        );
      };

  /// Opens the support mailbox with the art id (the "Report this image"
  /// route). Tests replace it.
  static Future<bool> Function(Uri uri) openMail = (uri) async => false;
}

/// Renders the widget under [boundaryKey] to a PNG (3x the card size).
Future<Uint8List?> capturePng(GlobalKey boundaryKey) async {
  final ctx = boundaryKey.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderRepaintBoundary) return null;
  final image = await box.toImage(pixelRatio: 3);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

/// The picture shared for a medal: art, medal name, event and category, and
/// the FitFlex name. The member's name is never on it; the time only when
/// the member switched it on.
class MedalShareCard extends StatelessWidget {
  const MedalShareCard({
    super.key,
    required this.art,
    required this.medalName,
    required this.eventLine,
    this.timeText,
  });

  final MedalArt art;
  final String medalName;
  final String eventLine;
  final String? timeText;

  static const double width = 320;
  static const double height = 400;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [FFTokens.brand700, FFTokens.brand800],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MedalBadge(art: art, size: 180, variant: 'm512'),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            medalName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            eventLine,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (timeText != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              timeText!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          const Text(
            'FitFlex',
            style: TextStyle(
              color: FFTokens.volt,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
