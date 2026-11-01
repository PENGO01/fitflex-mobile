import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../events_registration_gate.dart';

/// `/member/events/results` (events S6 spec §10.1, "My results"): the
/// member's own official results, newest first. Each row opens that
/// registration's result page.
class MemberEventResultsListPage extends StatefulWidget {
  const MemberEventResultsListPage({super.key, this.options});

  final EventsOptions? options;

  @override
  State<MemberEventResultsListPage> createState() =>
      _MemberEventResultsListPageState();
}

class _MemberEventResultsListPageState
    extends State<MemberEventResultsListPage> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _next;
  bool _moreBusy = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    if (!_options.results.enabled) {
      setState(() => _loading = false);
      return;
    }
    await _load();
  }

  List<Map<String, dynamic>> _rows(Object? v) => v is List
      ? [
          for (final e in v)
            if (e is Map) Map<String, dynamic>.from(e),
        ]
      : const [];

  Future<void> _load({bool more = false}) async {
    if (more) {
      setState(() => _moreBusy = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final json = await _api.listMyEventResults(cursor: more ? _next : null);
      if (!mounted) return;
      setState(() {
        _items = more
            ? [..._items, ..._rows(json['items'])]
            : _rows(json['items']);
        final c = json['nextCursor']?.toString() ?? '';
        _next = c.isEmpty ? null : c;
        _loading = false;
        _moreBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _moreBusy = false;
      });
    }
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.memberEvents);

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final Widget body;
    if (_loading) {
      body = FFSkeletonList(
        key: const Key('myresults-loading'),
        semanticLabel: context.tr('events.result.entry.myResults'),
      );
    } else if (_error != null && _items.isEmpty) {
      body = Center(
        child: FFErrorState(
          key: const Key('myresults-error'),
          message: errorMessage(FFLocaleScope.of(context), _error!),
          retryLabel: context.tr('common.retry'),
          onRetry: _load,
        ),
      );
    } else if (!_options.results.enabled) {
      body = Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: FFEmptyState(
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      );
    } else if (_items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: FFEmptyState(
          key: const Key('myresults-empty'),
          title: context.tr('events.result.empty.mine'),
        ),
      );
    } else {
      body = ListView(
        key: const Key('myresults-list'),
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        children: [
          for (final r in _items) _row(context, r, lang),
          if (_next != null)
            FFButton(
              key: const Key('myresults-more'),
              label: context.tr('events.loadMore'),
              variant: FFButtonVariant.secondary,
              loading: _moreBusy,
              onPressed: () => _load(more: true),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.result.entry.myResults')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: body,
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r, String lang) {
    final id = r['registrationId']?.toString() ?? '';
    final ms = r['elapsedMs'] is num ? (r['elapsedMs'] as num).toInt() : null;
    final rank = r['categoryRank'] is num
        ? (r['categoryRank'] as num).toInt()
        : null;
    final title = r['eventTitle']?.toString() ?? '';
    final cat = r['categoryName']?.toString() ?? '';
    final when = r['eventStartsAt'] ?? r['startsAt'];
    return FFActionTile(
      key: Key('myresult-$id'),
      icon: Icons.emoji_events_outlined,
      title: title.isEmpty ? context.tr('events.result.title') : title,
      subtitle: [
        if (cat.isNotEmpty) cat,
        if (ms != null) formatResultTime(ms),
        if (rank != null) '#$rank',
        if (when != null) formatDate(when, locale: lang),
      ].join(' · '),
      onTap: id.isEmpty
          ? null
          : () => context.push(AppRoutes.memberEventResultPath(id)),
    );
  }
}
