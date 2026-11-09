import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design_tokens.dart';
import '../i18n.dart';
import '../components/components.dart';
import '../ff_datetime.dart';
import '../formatters.dart';

/// Longest message the backend accepts (ENQUIRY_TEXT_MAX).
const enquiryTextMax = 1000;

/// One message of a member ↔ trainer conversation.
class EnquiryMessage {
  const EnquiryMessage({required this.from, required this.text, this.at});

  /// 'member' | 'trainer'
  final String from;
  final String text;
  final DateTime? at;

  factory EnquiryMessage.fromJson(Map<String, dynamic> j) => EnquiryMessage(
    from: j['from']?.toString() ?? 'member',
    text: j['text']?.toString() ?? '',
    at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal(),
  );

  static List<EnquiryMessage> listFrom(Object? engagement) {
    final raw = engagement is Map ? engagement['messages'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => EnquiryMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}

String _when(DateTime? at) {
  if (at == null) return '';
  final now = DateTime.now();
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  return sameDay
      ? formatTimeOfDay(at, locale: dateLanguage)
      : '${DateFormat('d MMM').format(at)}, '
            '${formatTimeOfDay(at, locale: dateLanguage)}';
}

/// The conversation as chat bubbles; [me] ('member' | 'trainer') is on the
/// right.
class EnquiryThread extends StatelessWidget {
  const EnquiryThread({super.key, required this.messages, required this.me});

  final List<EnquiryMessage> messages;
  final String me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, m) in messages.indexed)
          Align(
            key: Key('enquiry-message-$i'),
            alignment: m.from == me
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .78,
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: m.from == me
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(m.from == me ? 14 : 4),
                    bottomRight: Radius.circular(m.from == me ? 4 : 14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.text,
                      style: TextStyle(
                        color: m.from == me
                            ? scheme.onPrimary
                            : scheme.onSurface,
                        height: 1.35,
                      ),
                    ),
                    if (m.at != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _when(m.at),
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              (m.from == me
                                      ? scheme.onPrimary
                                      : scheme.onSurface)
                                  .withValues(alpha: .7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Text box + send button. [onSend] returns true when the message went out
/// (the box is then cleared).
class EnquiryReplyBox extends StatefulWidget {
  const EnquiryReplyBox({
    super.key,
    required this.onSend,
    this.hintKey = 'enquiry.replyHint',
    this.suggestions = const [],
  });

  final Future<bool> Function(String text) onSend;
  final String hintKey;

  /// Quick replies shown as chips above the box (tap fills the box).
  final List<String> suggestions;

  @override
  State<EnquiryReplyBox> createState() => _EnquiryReplyBoxState();
}

class _EnquiryReplyBoxState extends State<EnquiryReplyBox> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSend(text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.suggestions.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, s) in widget.suggestions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: ActionChip(
                      key: Key('enquiry-suggestion-$i'),
                      label: Text(s, overflow: TextOverflow.ellipsis),
                      onPressed: () => setState(() {
                        _ctrl.text = s;
                        _ctrl.selection = TextSelection.collapsed(
                          offset: s.length,
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('enquiry-reply-field'),
                controller: _ctrl,
                minLines: 1,
                maxLines: 5,
                maxLength: enquiryTextMax,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.tr(widget.hintKey),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('enquiry-send'),
              tooltip: context.tr('member.send'),
              onPressed: _busy ? null : _send,
              icon: _busy ? FFSpinner(size: 18) : const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}
