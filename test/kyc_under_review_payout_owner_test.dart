// Partner-neutral KYC reasons (fitflex-functions#245) and the shared-gym
// payout owner (fitflex-functions#247), in English and Swahili at 360 wide.
//
// #245: a partner may get the code `under_review` instead of a sensitive one
// in case.reasonCode, progress.nextAction.reasonCode / .reason and blocked
// progress.steps[].reason. The app says "Under review — please contact
// FitFlex support" with the contact-support action and never a reason note.
//
// #247: GET /owner/gyms adds `isPayoutOwner` per gym while the server flag
// is on; payout_not_ready may carry payout_owner_required or
// not_payout_owner (with gymId).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/owner/owner_shell.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_center_page.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_models.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/partner_progress.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/partner_progress_tracker.dart';
import 'package:fitflexmobile/shared/widgets/payout_owner_marker.dart';

// ── Words ───────────────────────────────────────────────────────────────────

const _reviewEn = 'Under review — please contact FitFlex support.';
const _reviewSw = 'Inakaguliwa — tafadhali wasiliana na msaada wa FitFlex.';
const _supportEn = 'Contact support';
const _supportSw = 'Wasiliana na msaada';
const _requiredEn =
    'This gym has more than one owner. FitFlex needs to name the payout '
    'owner before payouts can start.';
const _requiredSw =
    'Gym hii ina mmiliki zaidi ya mmoja. FitFlex inahitaji kumtaja mmiliki '
    'atakayepokea malipo kabla malipo hayajaanza.';
const _notOwnerEn = 'Another owner receives payouts for this gym.';
const _notOwnerSw = 'Mmiliki mwingine ndiye anayepokea malipo ya gym hii.';
const _markerEn = 'Payout owner';
const _markerSw = 'Mpokeaji wa malipo';

/// A sensitive note the server should never send with under_review; if one
/// slips through, the app still must not show it.
const _leakedNote = 'Suspected fraud: ID matches another account';

String _t(String lang, String en, String sw) => lang == 'sw' ? sw : en;

// ── Fixtures ────────────────────────────────────────────────────────────────

Map<String, dynamic> _step(String key, String state, {String? reason}) => {
  'key': key,
  'state': state,
  'reason': ?reason,
};

Map<String, dynamic> _progress(
  List<Map<String, dynamic>> steps,
  String current,
  Map<String, dynamic> next, {
  List<Map<String, dynamic>>? gyms,
}) => {'steps': steps, 'current': current, 'nextAction': next, 'gyms': ?gyms};

List<Map<String, dynamic>> _upTo(String current, {String state = 'current'}) {
  final out = <Map<String, dynamic>>[];
  var reached = false;
  for (final k in partnerStepKeys) {
    if (k == current) {
      reached = true;
      out.add(_step(k, state));
    } else {
      out.add(_step(k, reached ? 'todo' : 'done'));
    }
  }
  return out;
}

Map<String, dynamic> _allDone() => _progress(
  [for (final k in partnerStepKeys) _step(k, 'done')],
  'payoutReady',
  {'code': 'none'},
);

Map<String, dynamic> _overview({
  required String status,
  String? reasonCode,
  String? reasonNote,
  Map<String, dynamic>? progress,
}) => {
  'partnerType': 'trainer',
  'case': {
    'id': 'kyc_1',
    'status': status,
    'round': 1,
    'reasonCode': ?reasonCode,
    'reasonNote': ?reasonNote,
  },
  'people': const [],
  'documents': const [],
  'settlementAccounts': <Map<String, dynamic>>[],
  'checklist': {
    'sections': [
      {
        'key': 'identity',
        'items': [
          {'key': 'identity.fullName', 'by': 'partner', 'status': 'complete'},
        ],
      },
    ],
    'missing': const [],
    'readyToSubmit': false,
    'complete': true,
  },
  'progress': ?progress,
};

class _Repo extends VerificationRepository {
  _Repo(this.json) : super(ApiClient(baseUrl: 'http://localhost:0'));
  final Map<String, dynamic> json;

  @override
  Future<KycOverview> overview() async => KycOverview.fromJson(json);
}

/// Answers the owner earnings page with nothing to list.
class _EarningsApi extends ApiClient {
  _EarningsApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Map<String, dynamic>> ownerEarnings({String? gymId}) async => {
    'totalPaid': 0,
    'totalPending': 0,
  };

  @override
  Future<List<dynamic>> ownerSettlements({String? gymId}) async => const [];

  @override
  Future<List<dynamic>> ownerInvoices() async => const [];
}

// ── Hosts ───────────────────────────────────────────────────────────────────

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app(
  Widget home, {
  required String lang,
  ApiClient? api,
  OwnerData? owner,
}) {
  final client = api ?? ApiClient(baseUrl: 'http://localhost:0');
  Widget child = MaterialApp(
    theme: buildTheme(),
    supportedLocales: const [Locale('en'), Locale('sw')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
  if (owner != null) child = OwnerDataScope(data: owner, child: child);
  return AppScope(
    api: client,
    auth: AuthState(client),
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale()..set(Locale(lang)),
        child: child,
      ),
    ),
  );
}

Widget _tracker(
  Map<String, dynamic> progress, {
  void Function(PartnerNextAction)? onAction,
  bool compact = false,
}) => Scaffold(
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    child: PartnerProgressTracker(
      progress: PartnerProgress.tryParse(progress)!,
      compact: compact,
      onAction: onAction ?? (_) {},
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final lang in ['en', 'sw']) {
    final review = _t(lang, _reviewEn, _reviewSw);
    final support = _t(lang, _supportEn, _supportSw);

    group('under_review ($lang, 360)', () {
      testWidgets('contact_support: blocked step and next line say under '
          'review, with the support action', (tester) async {
        _phone(tester);
        final steps = _upTo('verified', state: 'blocked');
        steps[2]['reason'] = 'under_review';
        PartnerNextAction? pressed;
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(steps, 'verified', {
                'code': 'contact_support',
                'reason': 'under_review',
              }),
              onAction: (a) => pressed = a,
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Said once: the current step's reason lives in the next-action line.
        expect(find.text(review), findsOneWidget);
        expect(find.text(support), findsOneWidget);
        await tester.tap(find.byKey(const Key('partner-progress-action')));
        expect(pressed?.code, 'contact_support');
        expect(partnerActionIsSupport(pressed!), isTrue);
      });

      testWidgets('a later blocked step with under_review shows it', (
        tester,
      ) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(
                [
                  _step('registered', 'done'),
                  _step('approved', 'done'),
                  _step('verified', 'current'),
                  _step('payoutReady', 'blocked', reason: 'under_review'),
                ],
                'verified',
                {'code': 'kyc_under_review'},
              ),
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining(review), findsOneWidget);
      });

      testWidgets('changes requested with under_review: no reason, and the '
          'button contacts support', (tester) async {
        _phone(tester);
        PartnerNextAction? pressed;
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(_upTo('verified'), 'verified', {
                'code': 'kyc_changes_requested',
                'reasonCode': 'under_review',
              }),
              onAction: (a) => pressed = a,
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(review), findsOneWidget);
        // Not "FitFlex asked for changes…", not "Make changes".
        expect(find.textContaining('FitFlex asked for changes'), findsNothing);
        expect(find.textContaining('FitFlex imeomba mabadiliko'), findsNothing);
        expect(find.text(support), findsOneWidget);
        await tester.tap(find.byKey(const Key('partner-progress-action')));
        expect(pressed?.reasonCode, 'under_review');
        expect(partnerActionIsSupport(pressed!), isTrue);
      });

      testWidgets('compact banner says under review and fits', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(_upTo('verified'), 'verified', {
                'code': 'kyc_changes_requested',
                'reasonCode': 'under_review',
              }),
              compact: true,
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(review), findsOneWidget);
      });

      testWidgets('Verification centre without progress: under-review text '
          'and support button, never the note', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            VerificationCenterPage(
              repository: _Repo(
                _overview(
                  status: 'rejected',
                  reasonCode: 'under_review',
                  reasonNote: _leakedNote,
                ),
              ),
            ),
            lang: lang,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('kyc-status')), findsOneWidget);
        expect(find.text(review), findsOneWidget);
        expect(find.textContaining('Suspected fraud'), findsNothing);
        // Not the "was not approved" sentence either.
        expect(
          find.textContaining('Your verification was not approved'),
          findsNothing,
        );
        expect(find.byKey(const Key('kyc-status-support')), findsOneWidget);
        expect(find.text(support), findsOneWidget);
      });

      testWidgets('Verification centre with progress: the tracker says it '
          'once and no note card shows', (tester) async {
        _phone(tester);
        final steps = _upTo('verified', state: 'blocked');
        steps[2]['reason'] = 'under_review';
        await tester.pumpWidget(
          _app(
            VerificationCenterPage(
              repository: _Repo(
                _overview(
                  status: 'rejected',
                  reasonCode: 'under_review',
                  reasonNote: _leakedNote,
                  progress: _progress(steps, 'verified', {
                    'code': 'contact_support',
                    'reason': 'under_review',
                  }),
                ),
              ),
            ),
            lang: lang,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('kyc-status')), findsNothing);
        expect(find.text(review), findsOneWidget);
        expect(find.textContaining('Suspected fraud'), findsNothing);
      });

      testWidgets('suspended + under_review with progress: only the renew '
          'hint, no note', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            VerificationCenterPage(
              repository: _Repo(
                _overview(
                  status: 'suspended',
                  reasonCode: 'under_review',
                  reasonNote: _leakedNote,
                  progress: _progress(
                    _upTo('verified', state: 'blocked')
                      ..[2]['reason'] = 'under_review',
                    'verified',
                    {'code': 'contact_support', 'reason': 'under_review'},
                  ),
                ),
              ),
            ),
            lang: lang,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Suspected fraud'), findsNothing);
        expect(find.text(review), findsOneWidget);
      });
    });

    test('KYC under-review notice uses data.titleSw/bodySw in Swahili '
        '($lang)', () {
      // The shape fitflex-functions#245 sends for a sensitive decision.
      const data = {
        'reasonCode': 'under_review',
        'titleSw': 'Uthibitisho unakaguliwa',
        'bodySw':
            'Uthibitisho wako wa ushirika wa FitFlex unakaguliwa. '
            'Tafadhali wasiliana na msaada wa FitFlex.',
      };
      final text = localisedNoticeText(
        lang: lang,
        data: data,
        title: 'Verification under review',
        body:
            'Your FitFlex partner verification is under review. Please '
            'contact FitFlex support.',
      );
      expect(
        text.title,
        _t(lang, 'Verification under review', 'Uthibitisho unakaguliwa'),
      );
      expect(text.body, contains(_t(lang, 'Please contact', 'msaada')));
    });

    group('payout owner ($lang, 360)', () {
      final required = _t(lang, _requiredEn, _requiredSw);
      final notOwner = _t(lang, _notOwnerEn, _notOwnerSw);
      final marker = _t(lang, _markerEn, _markerSw);

      testWidgets('payout_owner_required on the overall line, with support', (
        tester,
      ) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(_upTo('payoutReady'), 'payoutReady', {
                'code': 'payout_not_ready',
                'reason': 'payout_owner_required',
                'gymId': 'g1',
              }),
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(required), findsOneWidget);
        expect(find.text(support), findsOneWidget);
      });

      testWidgets('not_payout_owner on its gym row, said once', (tester) async {
        _phone(tester);
        final coOwned = _progress(_upTo('payoutReady'), 'payoutReady', {
          'code': 'payout_not_ready',
          'reason': 'not_payout_owner',
          'gymId': 'g2',
        });
        final shared = _progress(_upTo('payoutReady'), 'payoutReady', {
          'code': 'payout_not_ready',
          'reason': 'payout_owner_required',
          'gymId': 'g3',
        });
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(
                _upTo('payoutReady'),
                'payoutReady',
                {
                  'code': 'payout_not_ready',
                  'reason': 'not_payout_owner',
                  'gymId': 'g2',
                },
                gyms: [
                  {'gymId': 'g1', 'name': 'Mbezi Fit', 'progress': _allDone()},
                  {
                    'gymId': 'g2',
                    'name': 'Sinza Strength and Conditioning Club',
                    'progress': coOwned,
                  },
                  {'gymId': 'g3', 'name': 'Kariakoo Gym', 'progress': shared},
                ],
              ),
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // The overall line is left out; each gym row says its own reason.
        expect(find.byKey(const Key('partner-progress-next')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('partner-progress-gym-g2')),
            matching: find.text(notOwner),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('partner-progress-gym-g3')),
            matching: find.text(required),
          ),
          findsOneWidget,
        );
        expect(find.text(notOwner), findsOneWidget);
      });

      testWidgets('payout_not_ready without a known reason keeps the old '
          'wording', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(_upTo('payoutReady'), 'payoutReady', {
                'code': 'payout_not_ready',
                'reason': 'no_owner_account',
              }),
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        expect(
          find.text(
            _t(
              lang,
              'Payouts aren’t ready yet. Contact FitFlex support.',
              'Malipo bado hayajawa tayari. Wasiliana na msaada wa FitFlex.',
            ),
          ),
          findsOneWidget,
        );
      });

      final gyms = <Map<String, dynamic>>[
        {
          'id': 'g1',
          'name': 'Mbezi Fit',
          'tier': 'standard',
          'isPayoutOwner': true,
        },
        {
          'id': 'g2',
          'name': 'Sinza Strong',
          'tier': 'standard',
          'isPayoutOwner': false,
        },
        // Flag off / older server: no field at all.
        {'id': 'g3', 'name': 'Kariakoo Gym', 'tier': 'standard'},
      ];

      testWidgets(
        'Manage gyms: the marker shows on the payout-owner gym only',
        (tester) async {
          _phone(tester);
          final owner = OwnerData()
            ..ownerGyms = gyms
            ..activeGymId = 'g1';
          await tester.pumpWidget(
            _app(
              const Scaffold(body: OwnerManageGymsPage()),
              lang: lang,
              owner: owner,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          // The marker sits on the cover photo, so it adds no height.
          expect(
            find.ancestor(
              of: find.byKey(const Key('owner-gym-payout-owner-g1')),
              matching: find.byType(AspectRatio),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('owner-gym-payout-owner-g1')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('owner-gym-payout-owner-g2')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('owner-gym-payout-owner-g3')),
            findsNothing,
          );
          expect(find.text(marker), findsOneWidget);
        },
      );

      testWidgets('gym picker: the marker shows next to the payout-owner gym', (
        tester,
      ) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(
            Scaffold(
              appBar: FFOwnerDashboardBar(
                selectedGymName: 'Mbezi Fit',
                initials: 'DO',
                ownerGyms: gyms,
                subtitleLabel: 'Dashboard',
              ),
              body: const SizedBox(),
            ),
            lang: lang,
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Mbezi Fit'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('owner-gym-picker-payout-owner-g1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('owner-gym-picker-payout-owner-g2')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('owner-gym-picker-payout-owner-g3')),
          findsNothing,
        );
      });

      for (final (active, shows) in [
        ('g1', true),
        ('g2', false),
        ('g3', false),
      ]) {
        testWidgets(
          'Earnings: marker ${shows ? 'shows' : 'hidden'} for $active',
          (tester) async {
            _phone(tester);
            final owner = OwnerData()
              ..ownerGyms = gyms
              ..activeGymId = active;
            await tester.pumpWidget(
              _app(
                const OwnerEarningsPage(),
                lang: lang,
                api: _EarningsApi(),
                owner: owner,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const Key('owner-earnings-payout-owner')),
              shows ? findsOneWidget : findsNothing,
            );
            if (shows) expect(find.text(marker), findsOneWidget);
          },
        );
      }
    });
  }

  test('isPayoutOwnerGym is true only for an explicit true', () {
    expect(isPayoutOwnerGym({'isPayoutOwner': true}), isTrue);
    expect(isPayoutOwnerGym({'isPayoutOwner': false}), isFalse);
    expect(isPayoutOwnerGym({'isPayoutOwner': 'true'}), isFalse);
    expect(isPayoutOwnerGym(const {}), isFalse);
    expect(isPayoutOwnerGym(null), isFalse);
  });
}
