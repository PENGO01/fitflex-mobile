// Events S6 (spec §10.4): the signed-in results board.
import 'package:fitflexmobile/screens/member/events/results/event_results_board_page.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 's3_support.dart';
import 's6_support.dart';

const _path = 'GET /events/evt_1/results';

Map<String, dynamic> _row(
  int? rank,
  String bib, {
  String? name,
  int? ms = 6728000,
  String status = 'finished',
  List<String> badges = const [],
}) => {
  'rank': rank,
  'bibNumber': bib,
  'displayName': name,
  'elapsedMs': ms,
  'finishStatus': status,
  'stage': 'official',
  'badges': badges,
};

Map<String, dynamic> _board({
  String stage = 'official',
  List<Map<String, dynamic>>? items,
  Map<String, dynamic>? mine,
  String? next,
  bool twoCategories = true,
}) => {
  'event': {'title': 'Dar Half Marathon', 'eventType': 'road'},
  'release': {'stage': stage, 'releasedAt': '2027-03-15T10:00:00Z'},
  'categories': [
    {'id': 'cat_21', 'name': '21K'},
    if (twoCategories) {'id': 'cat_10', 'name': '10K'},
  ],
  'items':
      items ??
      [
        _row(1, '1001', name: 'Asha M.'),
        _row(2, '1002', name: null, ms: 6800000),
        _row(null, '1003', name: 'Juma K.', ms: null, status: 'dnf'),
        _row(null, '1004', name: 'Neema P.', ms: null, status: 'dq'),
        _row(5, '1005', name: 'Baraka T.', ms: 7000000, badges: ['corrected']),
      ],
  'mine': mine,
  'nextCursor': next,
};

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  Size size = const Size(375, 2400),
  EventsOptions? options,
}) => pumpPage(
  tester,
  api,
  EventResultsBoardPage(
    eventId: 'evt_1',
    options: options ?? optsS6(),
    debounce: Duration.zero,
  ),
  user: member,
  lang: lang,
  size: size,
  extraRoutes: s6Routes,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
  });
  tearDown(() => debugEventsDiscoveryOverride = null);

  apiTest(
    'rows: rank, name or "Runner {bib}", bib and time; banner and footer',
    (tester, api) async {
      api.on(_path, _board());
      await _pump(tester, api);
      expect(find.text('Official results'), findsOneWidget);
      expect(find.text('Asha M.'), findsOneWidget);
      // A person who chose not to show their name is "Runner {bib}".
      expect(find.text('Runner 1002'), findsOneWidget);
      expect(find.text('1:52:08'), findsOneWidget);
      expect(
        find.text('Names appear only for people who chose to show them.'),
        findsOneWidget,
      );
      expect(find.text('Corrected'), findsOneWidget);
    },
  );

  apiTest('DNF and DQ rows show a word where the time would be', (
    tester,
    api,
  ) async {
    api.on(_path, _board());
    await _pump(tester, api);
    expect(find.text('Did not finish'), findsOneWidget);
    expect(find.text('Disqualified'), findsOneWidget);
    expect(find.text('Juma K.'), findsOneWidget);
  });

  apiTest('provisional banner', (tester, api) async {
    api.on(_path, _board(stage: 'provisional'));
    await _pump(tester, api);
    expect(find.text('Provisional results'), findsOneWidget);
  });

  apiTest('own row is pinned first as "You"', (tester, api) async {
    api.on(_path, _board(mine: {'rank': 2, 'bibNumber': '1002'}));
    await _pump(tester, api);
    final mine = find.byKey(const Key('board-mine'));
    expect(mine, findsOneWidget);
    expect(
      find.descendant(of: mine, matching: find.text('You')),
      findsOneWidget,
    );
    // It borrows the time of the matching listed row.
    expect(
      find.descendant(of: mine, matching: find.text('1:53:20')),
      findsOneWidget,
    );
    // And it sits above the first listed row.
    expect(
      tester.getTopLeft(mine).dy,
      lessThan(tester.getTopLeft(find.text('Asha M.')).dy),
    );
  });

  apiTest('row semantics read rank, bib, name and time in words', (
    tester,
    api,
  ) async {
    api.on(_path, _board());
    await _pump(tester, api);
    expect(
      find.bySemanticsLabel('Rank 1, Bib 1001, Asha M., 1 hr 52 min 8 sec'),
      findsOneWidget,
    );
  });

  apiTest('categories switch the list; the search is sent after a pause', (
    tester,
    api,
  ) async {
    api.on(_path, _board());
    await _pump(tester, api);
    // The first request lets the server pick its default category.
    expect(api.requests.last.query, isNot(contains('categoryId')));
    await tester.tap(find.text('10K'));
    await tester.pumpAndSettle();
    expect(api.requests.last.query, contains('categoryId=cat_10'));
    await tester.enterText(find.byKey(const Key('board-search')), '1002');
    await tester.pumpAndSettle();
    expect(api.requests.last.query, contains('q=1002'));
  });

  apiTest('"Load more" appends by cursor', (tester, api) async {
    api.onCall(_path, (req) {
      if (req.query.contains('cursor=c2')) {
        return _board(items: [_row(6, '1006', name: 'Zawadi L.')]);
      }
      return _board(next: 'c2');
    });
    await _pump(tester, api);
    await tester.ensureVisible(find.byKey(const Key('board-load-more')));
    await tester.tap(find.byKey(const Key('board-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Zawadi L.'), findsOneWidget);
    expect(find.text('Asha M.'), findsOneWidget);
    expect(find.byKey(const Key('board-load-more')), findsNothing);
  });

  apiTest('not released: the empty state, no rows', (tester, api) async {
    api.on(_path, _board(stage: 'none', items: const []));
    await _pump(tester, api);
    expect(find.text("Results aren't published yet."), findsOneWidget);
    expect(find.byKey(const Key('board-banner')), findsNothing);
  });

  apiTest('offline shows the saved first page, labelled', (tester, api) async {
    api.on(_path, _board());
    await _pump(tester, api);
    api.onCall(_path, (_) => throw StateError('SocketException: offline'));
    await _pump(tester, api);
    expect(find.byKey(const Key('board-cached')), findsOneWidget);
    expect(find.textContaining('Saved on this phone'), findsOneWidget);
    expect(find.text('Asha M.'), findsOneWidget);
  });

  apiTest('signed out (401): the sign-in prompt', (tester, api) async {
    api.fail(_path, 401, {'error': 'unauthorized'});
    await _pump(tester, api);
    expect(find.text('Sign in to see the results.'), findsOneWidget);
  });

  apiTest('flag off: no request, unavailable', (tester, api) async {
    await _pump(tester, api, options: optsS6(public: false));
    expect(api.sent('GET', '/events/evt_1/results'), isFalse);
    expect(find.byKey(const Key('board-unavailable')), findsOneWidget);
  });

  apiTest('desktop: a centred 720 column; Swahili banner', (tester, api) async {
    api.on(_path, _board());
    await _pump(tester, api, lang: 'sw', size: const Size(1200, 1600));
    expect(find.text('Matokeo rasmi'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('board-scroll'))).width, 720);
  });
}
