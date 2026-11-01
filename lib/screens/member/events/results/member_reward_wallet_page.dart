import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_reward.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/shop_checkout.dart';
import '../events_registration_gate.dart';
import 'results_widgets.dart';

enum _Phase { loading, ready, error }

/// `/member/events/rewards` (events S6 spec §10.5): the rewards the member
/// can claim, what they have claimed, and a plain history. There is no
/// points number anywhere (D44): each line is one reward.
class MemberRewardWalletPage extends StatefulWidget {
  const MemberRewardWalletPage({super.key, this.options});

  final EventsOptions? options;

  @override
  State<MemberRewardWalletPage> createState() => _MemberRewardWalletPageState();
}

class _MemberRewardWalletPageState extends State<MemberRewardWalletPage> {
  _Phase _phase = _Phase.loading;
  RewardWallet _wallet = const RewardWallet();
  List<RewardLedgerLine> _history = const [];
  String? _historyNext;
  bool _historyFailed = false;
  DateTime? _savedAt;
  bool _offline = false;
  Object? _error;
  String? _expanded;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    if (!_options.results.rewards) {
      setState(() => _phase = _Phase.ready);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _phase = _phase == _Phase.ready ? _phase : _Phase.loading;
      _error = null;
    });
    try {
      final json = await _api.myEventRewards();
      if (!mounted) return;
      // A perk code is never written to the phone.
      await EventsCache.putMine(
        memberCacheKey(context, 'wallet'),
        walletWithoutCodes(json),
      );
      if (!mounted) return;
      setState(() {
        _wallet = RewardWallet.fromJson(json);
        _offline = false;
        _savedAt = null;
        _phase = _Phase.ready;
      });
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      final cached = isNetworkError(e)
          ? await EventsCache.getFreshMine(memberCacheKey(context, 'wallet'))
          : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _wallet = RewardWallet.fromJson(cached.$2);
          _offline = true;
          _savedAt = cached.$1;
          _phase = _Phase.ready;
        });
        return;
      }
      setState(() {
        _error = e;
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _loadHistory({bool more = false}) async {
    try {
      final json = await _api.myEventRewardLedger(
        cursor: more ? _historyNext : null,
      );
      if (!mounted) return;
      final page = RewardLedgerPage.fromJson(json);
      setState(() {
        _history = more ? [..._history, ...page.items] : page.items;
        _historyNext = page.nextCursor;
        _historyFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  Future<void> _claim(RewardAvailable r) async {
    final redemption = await showFFSheet<RewardRedemptionView>(
      context,
      title: context.tr('events.rewards.claim.confirm'),
      wideDialogWidth: 480,
      child: RewardRedeemSheet(reward: r, api: _api),
    );
    if (redemption == null || !mounted) return;
    setState(() => _expanded = redemption.id);
    await _load();
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.memberEvents);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.rewards.title')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('wallet-loading'),
          semanticLabel: context.tr('events.rewards.title'),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('wallet-error'),
            message: errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _ => _content(context),
      },
    );
  }

  Widget _content(BuildContext context) {
    if (!_options.results.rewards) {
      return Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: FFEmptyState(
          key: const Key('wallet-unavailable'),
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      );
    }
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final w = _wallet;
    return ListView(
      key: const Key('wallet-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_offline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: FFAlert(
                      key: const Key('wallet-cached'),
                      tone: FFAlertTone.warning,
                      message:
                          '${context.tr('events.rewards.offline')} · '
                          '${context.tr('events.result.cached').replaceFirst('{time}', formatDateTime(_savedAt, locale: lang))}',
                    ),
                  ),
                if (w.isEmpty)
                  FFEmptyState(
                    key: const Key('wallet-empty'),
                    title: context.tr('events.rewards.empty'),
                    icon: Icons.card_giftcard,
                  ),
                if (w.available.isNotEmpty) ...[
                  FFSectionTitle(context.tr('events.rewards.available')),
                  for (final r in w.available) _availableCard(context, r, lang),
                ],
                if (w.redemptions.isNotEmpty) ...[
                  FFSectionTitle(context.tr('events.rewards.claimed')),
                  for (final r in w.redemptions)
                    RedemptionCard(
                      key: Key('redemption-${r.id}'),
                      redemption: r,
                      initiallyExpanded: _expanded == r.id || r.isReserved,
                    ),
                ],
                if (w.expired.isNotEmpty) ...[
                  FFSectionTitle(context.tr('events.rewards.status.expired')),
                  for (final r in w.expired)
                    FFCard(
                      key: Key('expired-${r.definitionId}'),
                      child: Text(
                        '${r.title.of(lang)} · '
                        '${context.tr('events.rewards.expiredOn').replaceFirst('{date}', formatDate(r.nextExpiry, locale: lang))}',
                      ),
                    ),
                ],
                if (_history.isNotEmpty || _historyFailed) ...[
                  FFSectionTitle(context.tr('events.rewards.history')),
                  for (final h in _history)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: FFTokens.spacingXs,
                      ),
                      child: Text(
                        '${context.tr('events.rewards.entry.${_entryKey(h.entryType)}')}'
                        ' · ${h.title.of(lang)}'
                        ' · ${formatDate(h.occurredAt, locale: lang)}',
                        key: Key('history-${h.id}'),
                      ),
                    ),
                  if (_historyNext != null)
                    FFButton(
                      label: context.tr('events.loadMore'),
                      variant: FFButtonVariant.ghost,
                      onPressed: () => _loadHistory(more: true),
                    ),
                  if (_historyFailed) Text(context.tr('events.loadMoreFailed')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _entryKey(String t) =>
      const {'earn', 'redeem', 'expire', 'reverse'}.contains(t) ? t : 'earn';

  Widget _availableCard(BuildContext context, RewardAvailable r, String lang) {
    final tt = Theme.of(context).textTheme;
    final terms = r.terms.of(lang).trim();
    return FFCard(
      key: Key('reward-${r.definitionId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.title.of(lang), style: tt.titleSmall),
          if (r.nextExpiry != null)
            Text(
              context
                  .tr('events.rewards.expires')
                  .replaceFirst(
                    '{date}',
                    formatDate(r.nextExpiry, locale: lang),
                  ),
              style: tt.bodySmall,
            ),
          if (terms.isNotEmpty)
            TextButton(
              key: Key('reward-terms-${r.definitionId}'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => showFFSheet<void>(
                context,
                title: context.tr('events.rewards.terms'),
                wideDialogWidth: 480,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingMd),
                  child: SingleChildScrollView(child: Text(terms)),
                ),
              ),
              child: Text(context.tr('events.rewards.terms')),
            ),
          FFButton(
            key: Key('reward-claim-${r.definitionId}'),
            label: context.tr('events.rewards.claim'),
            onPressed: _offline || !r.canClaim ? null : () => _claim(r),
          ),
          if (_offline)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('events.rewards.offline'),
                style: tt.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// What claiming does, in words, then **Claim**; shows the certificate or the
/// code afterwards. The `Idempotency-Key` is made once for the sheet, so a
/// second tap or a retry is the same claim.
class RewardRedeemSheet extends StatefulWidget {
  const RewardRedeemSheet({super.key, required this.reward, required this.api});

  final RewardAvailable reward;
  final ApiClient api;

  @override
  State<RewardRedeemSheet> createState() => _RewardRedeemSheetState();
}

class _RewardRedeemSheetState extends State<RewardRedeemSheet> {
  bool _sending = false;
  String? _error;
  RewardRedemptionView? _done;
  final String _key = newCheckoutKey();

  Future<void> _claim() async {
    final locale = FFLocaleScope.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final json = await widget.api.claimEventReward(
        widget.reward.definitionId,
        idempotencyKey: _key,
      );
      final r = RewardRedemptionView.fromJson(
        json['redemption'] is Map ? json['redemption'] : json,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _done =
            r ??
            RewardRedemptionView(
              id: _key,
              definitionId: widget.reward.definitionId,
              title: widget.reward.title,
              redeemMode: widget.reward.redeemMode,
            );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = errorMessage(locale, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final r = widget.reward;
    final done = _done;
    return Padding(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.title.of(lang),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            if (done == null) ...[
              if (r.terms.of(lang).trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                  child: Text(r.terms.of(lang)),
                ),
              Text(
                context.tr(
                  r.isPerk
                      ? 'events.rewards.claim.bodyPerk'
                      : 'events.rewards.claim.bodyCertificate',
                ),
                key: const Key('claim-explain'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                  child: Semantics(
                    liveRegion: true,
                    child: FFAlert(
                      key: const Key('claim-error'),
                      tone: FFAlertTone.error,
                      message: _error!,
                    ),
                  ),
                ),
              const SizedBox(height: FFTokens.spacingMd),
              FFButton(
                key: const Key('claim-confirm'),
                label: context.tr('events.rewards.claim'),
                fullWidth: true,
                loading: _sending,
                onPressed: _sending ? null : _claim,
              ),
            ] else ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  context.tr('events.rewards.claim.done'),
                  key: const Key('claim-done'),
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              RedemptionCard(redemption: done, initiallyExpanded: true),
              FFButton(
                key: const Key('claim-close'),
                label: context.tr('common.close'),
                variant: FFButtonVariant.secondary,
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(done),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A claimed reward: a certificate (shareable picture made on the phone) or a
/// perk code (big monospace block, copy button, instructions, expiry).
class RedemptionCard extends StatefulWidget {
  const RedemptionCard({
    super.key,
    required this.redemption,
    this.initiallyExpanded = false,
  });

  final RewardRedemptionView redemption;
  final bool initiallyExpanded;

  @override
  State<RedemptionCard> createState() => _RedemptionCardState();
}

class _RedemptionCardState extends State<RedemptionCard> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _sharing = true);
    try {
      final png = await capturePng(_cardKey);
      if (png == null) return;
      await EventShareActions.shareImage(
        png,
        'fitflex-certificate-${widget.redemption.id}.png',
      );
    } catch (e) {
      snack.error(errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.redemption;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final statusKey = switch (r.status) {
      'reserved' => 'events.rewards.status.reserved',
      'redeemed' => 'events.rewards.status.redeemed',
      'expired' => 'events.rewards.status.expired',
      'cancelled' => 'events.rewards.status.cancelled',
      _ => 'events.rewards.status.redeemed',
    };
    final name = AppScope.of(context).auth.user?['name']?.toString() ?? '';
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.title.of(lang), style: tt.titleSmall)),
              const SizedBox(width: FFTokens.spacingXs),
              Flexible(
                child: FFBadge(
                  label: context.tr(statusKey),
                  tone: r.status == 'reserved'
                      ? FFBadgeTone.warning
                      : r.status == 'redeemed'
                      ? FFBadgeTone.success
                      : FFBadgeTone.gray,
                  dot: true,
                  wrap: true,
                ),
              ),
            ],
          ),
          if (widget.initiallyExpanded) ...[
            const SizedBox(height: FFTokens.spacingSm),
            if (r.isCertificate && r.status == 'redeemed') ...[
              Center(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: _CertificateCard(
                    name: name,
                    title: r.title.of(lang),
                    eventTitle: r.eventTitle,
                    resultLine: r.resultLine,
                    date: formatDate(r.redeemedAt, locale: lang, fallback: ''),
                  ),
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFButton(
                key: const Key('certificate-share'),
                label: context.tr('common.share'),
                icon: Icons.ios_share,
                variant: FFButtonVariant.secondary,
                loading: _sharing,
                onPressed: _share,
              ),
            ],
            if (!r.isCertificate && r.isReserved && r.code != null) ...[
              Text(context.tr('events.rewards.code'), style: tt.labelMedium),
              Container(
                key: const Key('reward-code'),
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                child: SelectableText(
                  r.code!,
                  textAlign: TextAlign.center,
                  style: tt.headlineMedium?.copyWith(
                    fontFamily: FFTokens.fontMono,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FFButton(
                  key: const Key('reward-code-copy'),
                  label: context.tr('events.rewards.code.copy'),
                  icon: Icons.copy_outlined,
                  variant: FFButtonVariant.ghost,
                  onPressed: () async {
                    final snack = FFSnack.of(context);
                    final copied = context.tr('events.rewards.code.copied');
                    await Clipboard.setData(ClipboardData(text: r.code!));
                    snack.success(copied);
                  },
                ),
              ),
              Text(
                context.tr('events.rewards.code.help'),
                style: tt.bodyMedium,
              ),
              if (r.expiresAt != null)
                Text(
                  context
                      .tr('events.rewards.expires')
                      .replaceFirst(
                        '{date}',
                        formatDate(r.expiresAt, locale: lang),
                      ),
                  key: const Key('reward-expiry'),
                  style: tt.bodySmall,
                ),
            ],
            if (r.status == 'expired')
              Text(
                context
                    .tr('events.rewards.expiredOn')
                    .replaceFirst(
                      '{date}',
                      formatDate(r.expiresAt, locale: lang),
                    ),
                style: tt.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.name,
    required this.title,
    this.eventTitle,
    this.resultLine,
    this.date = '',
  });

  final String name;
  final String title;
  final String? eventTitle;
  final String? resultLine;
  final String date;

  @override
  Widget build(BuildContext context) {
    const ink = TextStyle(color: Colors.white);
    return Container(
      width: 320,
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [FFTokens.brand700, FFTokens.brand800],
        ),
      ),
      child: Column(
        children: [
          Text(
            context.tr('events.rewards.certificate'),
            textAlign: TextAlign.center,
            style: ink.copyWith(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (name.isNotEmpty)
            Text(
              name,
              textAlign: TextAlign.center,
              style: ink.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: ink.copyWith(fontSize: 16),
          ),
          if ((eventTitle ?? '').isNotEmpty)
            Text(
              eventTitle!,
              textAlign: TextAlign.center,
              style: ink.copyWith(fontSize: 14, color: Colors.white70),
            ),
          if ((resultLine ?? '').isNotEmpty)
            Text(
              resultLine!,
              textAlign: TextAlign.center,
              style: ink.copyWith(fontSize: 14, color: Colors.white70),
            ),
          if (date.isNotEmpty)
            Text(
              date,
              textAlign: TextAlign.center,
              style: ink.copyWith(fontSize: 12, color: Colors.white70),
            ),
          const SizedBox(height: FFTokens.spacingMd),
          const Text(
            'FitFlex',
            style: TextStyle(
              color: FFTokens.volt,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
