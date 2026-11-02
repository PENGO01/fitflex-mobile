// Events S7 (spec §4, §10.2, §13 AC-W22): the waitlist on the phone. Models
// read tolerant JSON, every string is in both languages, the two glossary
// clashes are fixed, push notices open the right screen, the detail bar offers
// the waitlist only while the server says so, the join flow has no payment
// step, the offer card pays through the existing order page, leave and
// reconfirm work, offline shows the saved copy and blocks writes.
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/events/member_event_detail_page.dart';
import 'package:fitflexmobile/screens/member/events/member_event_order_page.dart';
import 'package:fitflexmobile/screens/member/events/member_event_orders_page.dart';
import 'package:fitflexmobile/screens/member/events/register/self_profile.dart';
import 'package:fitflexmobile/screens/member/events/waitlist/member_event_waitlist_join_page.dart';
import 'package:fitflexmobile/screens/member/events/waitlist/member_event_waitlist_view.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/event_detail.dart';
import 'package:fitflexmobile/shared/events/event_order.dart';
import 'package:fitflexmobile/shared/events/event_time.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events/waitlist.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

EventsOptions optsWl({bool waitlist = true, bool registration = true}) =>
    EventsOptions.fromJson({
      ...optionsS3,
      'registration': registration,
      'waitlist': {
        'enabled': waitlist,
        'offerHours': 12,
        'maxActivePerUser': 5,
      },
    });

/// A sold-out event whose `tt_early` ticket has [state] as its waitlist state.
Map<String, dynamic> soldOutDetail({
  String state = 'open',
  String availability = 'sold_out',
}) {
  final d = detail('evt_1', availability: availability, registration: true);
  final cats = [
    for (final c in d['categories'] as List)
      {
        ...(c as Map<String, dynamic>),
        'ticketTypes': [
          for (final t in c['ticketTypes'] as List)
            (t as Map)['id'] == 'tt_early'
                ? {
                    ...t,
                    'availability': 'sold_out',
                    'waitlist': {'state': state},
                  }
                : t,
        ],
      },
  ];
  return {...d, 'categories': cats};
}

Map<String, dynamic> entryJson({
  String id = 'wl_1',
  String status = 'waiting',
  int? position = 3,
  Map<String, dynamic>? offer,
  String? blockedReason,
  String? endedReason,
}) => {
  'id': id,
  'eventId': 'evt_1',
  'eventTitle': 'Dar Half Marathon',
  'startsAt': '2027-03-14T03:30:00Z',
  'timezone': 'Africa/Dar_es_Salaam',
  'ticketTypeId': 'tt_early',
  'ticketTypeName': 'Early bird',
  'categoryName': '21K Half Marathon',
  'status': status,
  'position': ?position,
  'joinedAt': '2027-03-09T10:00:00Z',
  'blockedReason': ?blockedReason,
  'offer': ?offer,
  'endedReason': ?endedReason,
};

const _offer = {
  'orderId': 'ord_77',
  'expiresAt': '2027-03-10T15:00:00Z',
  'amountTzs': 20000,
  'currency': 'TZS',
};

Map<String, dynamic> listJson(List<Map<String, dynamic>> items) => {
  'items': items,
  'serverTime': '2027-03-10T12:00:00Z',
};

const _profile = RegistrationSelfProfile(
  firstName: 'Amina',
  lastName: 'Mushi',
  phone: '+255712345678',
  dateOfBirth: '1990-05-04',
  gender: 'female',
);

Finder _cta(String text) => find.descendant(
  of: find.byKey(const Key('event-cta')),
  matching: find.text(text),
);

final _waitlistRoutes = <RouteBase>[
  // Before :eventId, as in the app router.
  GoRoute(
    path: AppRoutes.memberEventWaitlist,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-WAITLIST')),
  ),
  ...s3Routes,
];

const wlKeys = <String>[
  'events.waitlist.cta.join',
  'events.waitlist.cta.hint',
  'events.waitlist.cta.joined',
  'events.waitlist.join.title',
  'events.waitlist.join.pickTicket',
  'events.waitlist.join.details',
  'events.waitlist.join.rules',
  'events.waitlist.join.one',
  'events.waitlist.join.price',
  'events.waitlist.join.button',
  'events.waitlist.join.busy',
  'events.waitlist.joined.title',
  'events.waitlist.joined.position',
  'events.waitlist.joined.body',
  'events.waitlist.joined.view',
  'events.waitlist.joined.back',
  'events.waitlist.status.waiting',
  'events.waitlist.status.offered',
  'events.waitlist.status.converted',
  'events.waitlist.status.expired',
  'events.waitlist.status.declined',
  'events.waitlist.status.left',
  'events.waitlist.status.removed',
  'events.waitlist.status.closed',
  'events.waitlist.ended.sale_closed',
  'events.waitlist.ended.event_cancelled',
  'events.waitlist.ended.organizer_closed',
  'events.waitlist.ended.registered_elsewhere',
  'events.waitlist.ended.not_eligible',
  'events.waitlist.offer.title',
  'events.waitlist.offer.body',
  'events.waitlist.offer.pay',
  'events.waitlist.offer.chip',
  'events.waitlist.offer.passed',
  'events.waitlist.leave.button',
  'events.waitlist.leave.title',
  'events.waitlist.leave.body',
  'events.waitlist.leave.offeredBody',
  'events.waitlist.leave.done',
  'events.waitlist.error.not_sold_out',
  'events.waitlist.error.already_registered',
  'events.waitlist.error.full',
  'events.waitlist.error.lapse_limit',
  'events.waitlist.error.limit',
  'events.waitlist.error.verification',
  'events.waitlist.error.unavailable',
  'events.waitlist.error.payment_pending',
  'events.waitlist.error.rate',
  'events.waitlist.offline',
  'events.waitlist.reconfirm.banner',
  'events.waitlist.reconfirm.button',
  'events.waitlist.reconfirm.done',
  'events.waitlist.list.title',
  'events.waitlist.list.empty',
  'events.waitlist.sem.position',
  'events.privacy.analytics',
  'inbox.open.eventWaitlist',
  'inbox.open.eventWaitlistOffer',
];

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    debugPhotoHeroUiOverride = false;
    debugDeviceOffsetMinutesOverride = 180;
    EventsCache.reset();
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    debugPhotoHeroUiOverride = null;
    debugDeviceOffsetMinutesOverride = null;
    EventsAnalytics.debugSink = null;
  });

  group('models', () {
    test('options: an older server has no waitlist or analytics block', () {
      final o = EventsOptions.fromJson(optionsS3);
      expect(o.waitlist.enabled, isFalse);
      expect(o.analytics.enabled, isFalse);
      final on = EventsOptions.fromJson({
        ...optionsS3,
        'waitlist': {'enabled': true, 'offerHours': 6, 'maxActivePerUser': 3},
        'analytics': {'enabled': true},
      });
      expect(on.waitlist.enabled, isTrue);
      expect(on.waitlist.offerHours, 6);
      expect(on.waitlist.maxActivePerUser, 3);
      expect(on.analytics.enabled, isTrue);
    });

    test('ticket type: waitlist state reads, missing means none', () {
      final d = EventDetail.fromJson(soldOutDetail());
      final early = d.categories.first.ticketTypes.first;
      expect(early.waitlistState, 'open');
      expect(early.canJoinWaitlist, isTrue);
      final plain = EventDetail.fromJson(detail('evt_1'));
      expect(plain.categories.first.ticketTypes.first.waitlistState, 'none');
      expect(plain.categories.first.ticketTypes.first.canJoinWaitlist, isFalse);
      final closed = EventDetail.fromJson(soldOutDetail(state: 'closed'));
      expect(
        closed.categories.first.ticketTypes.first.canJoinWaitlist,
        isFalse,
      );
    });

    test('order: source waitlist is read; absent is null', () {
      final o = EventOrder.fromJson({
        ...(orderJson()['order'] as Map),
        'source': 'waitlist',
      });
      expect(o.fromWaitlist, isTrue);
      expect(EventOrder.fromJson(orderJson()['order'] as Map).source, isNull);
    });

    test('entries and the page read the contract fields', () {
      final p = WaitlistPage.fromJson(
        listJson([
          entryJson(),
          entryJson(
            id: 'wl_2',
            status: 'offered',
            position: null,
            offer: _offer,
          ),
          entryJson(id: 'wl_3', status: 'closed', endedReason: 'sale_closed'),
          entryJson(id: 'wl_4', blockedReason: 'reconsent'),
          {'id': 'wl_5', 'status': 'something_new'},
        ]),
      );
      expect(p.serverTime, DateTime.utc(2027, 3, 10, 12));
      expect(p.items.map((e) => e.status), [
        WaitlistStatus.waiting,
        WaitlistStatus.offered,
        WaitlistStatus.closed,
        WaitlistStatus.waiting,
        WaitlistStatus.other,
      ]);
      expect(p.items[0].position, 3);
      expect(p.items[1].offer!.orderId, 'ord_77');
      expect(p.items[1].offer!.expiresAt, DateTime.utc(2027, 3, 10, 15));
      expect(p.items[3].needsReconsent, isTrue);
      expect(p.items[4].status.wire, 'closed');
      expect(WaitlistPage.fromJson(const {}).items, isEmpty);
    });

    test('the join body has the ticket, one participant and the consent', () {
      final body = waitlistJoinBody(
        ticketTypeId: 'tt_early',
        participant: {'firstName': 'A'},
        consentTextVersion: 'v1',
        locale: 'sw',
      );
      expect(body['ticketTypeId'], 'tt_early');
      expect(body['participants'], hasLength(1));
      expect(body['consent'], {'accepted': true, 'textVersion': 'v1'});
      expect(body['locale'], 'sw');
      expect(
        waitlistJoinBody(
          ticketTypeId: 't',
          participant: {},
          consentTextVersion: 'v',
        ).containsKey('locale'),
        isFalse,
      );
    });
  });

  group('copy', () {
    test('every waitlist key is in both languages with the same slots', () {
      final slot = RegExp(r'\{[a-z]+\}');
      for (final k in wlKeys) {
        final en = FFLocale.textOf('en', k);
        final sw = FFLocale.textOf('sw', k);
        expect(en, isNotNull, reason: '$k missing in en');
        expect(sw, isNotNull, reason: '$k missing in sw');
        expect(
          slot.allMatches(sw!).map((m) => m[0]).toSet(),
          slot.allMatches(en!).map((m) => m[0]).toSet(),
          reason: 'placeholders of $k',
        );
      }
    });

    test('glossary clashes are fixed (S7 spec §10.4)', () {
      expect(FFLocale.textOf('sw', 'error.offlineTitle'), 'Hakuna intaneti');
      final hint = FFLocale.textOf('sw', 'events.cta.soldOutHint')!;
      expect(hint.toLowerCase(), isNot(contains('nafasi')));
      expect(hint, contains('tiketi'));
    });

    test('Swahili waitlist copy never uses "nafasi" or "ofa"', () {
      for (final k in wlKeys) {
        final sw = FFLocale.textOf('sw', k)!.toLowerCase();
        expect(sw, isNot(contains('nafasi')), reason: k);
        expect(RegExp(r'\bofa\b').hasMatch(sw), isFalse, reason: k);
      }
    });
  });

  group('routes and push', () {
    test('the waitlist route is registered before :eventId', () {
      expect(AppRoutes.memberEventWaitlist, '/member/events/waitlist');
      expect(
        AppRoutes.memberEventWaitlistJoinPath('e1', ticketTypeId: 't 1'),
        '/member/events/e1/register?mode=waitlist&ticketTypeId=t%201',
      );
      expect(
        AppRoutes.memberEventWaitlistJoinPath('e1'),
        '/member/events/e1/register?mode=waitlist',
      );
    });

    test('offer and reminder open the order; the rest open the waitlist', () {
      for (final type in const [
        'event_waitlist_offer',
        'event_waitlist_offer_reminder',
      ]) {
        expect(
          memberRouteFor(deepLink: '', type: type, orderId: 'o1'),
          '/member/events/orders/o1',
        );
        expect(
          memberRouteFor(deepLink: '', type: type),
          '/member/events/waitlist',
        );
        expect(
          memberRouteFor(deepLink: '', type: type, orderId: 'bad id!'),
          '/member/events/waitlist',
        );
        expect(memberLinkFor(deepLink: '', type: type), 'eventWaitlistOffer');
      }
      for (final type in const [
        'event_waitlist_joined',
        'event_waitlist_offer_expired',
        'event_waitlist_closed',
        'event_waitlist_removed',
      ]) {
        expect(
          memberRouteFor(deepLink: '', type: type, orderId: 'o1'),
          '/member/events/waitlist',
        );
        expect(memberLinkFor(deepLink: '', type: type), 'eventWaitlist');
      }
    });

    test('a tapped offer push goes to the order for a member', () {
      final t = pushTargetFor(
        role: 'member',
        data: {'type': 'event_waitlist_offer', 'orderId': 'ord_77'},
      );
      expect(t.location, '/member/events/orders/ord_77');
      expect(t.go, isTrue);
    });
  });

  group('event detail bar', () {
    Future<PageHost> pump(
      WidgetTester tester,
      RecordingApi api, {
      EventsOptions? options,
      String lang = 'en',
    }) => pumpPage(
      tester,
      api,
      MemberEventDetailPage(
        eventId: 'evt_1',
        options: options ?? optsWl(),
        now: DateTime.utc(2027, 3, 10, 12),
      ),
      user: member,
      lang: lang,
      size: const Size(375, 812),
      extraRoutes: _waitlistRoutes,
      keepRequests: true,
    );

    apiTest('sold out with an open waitlist offers Join waitlist', (
      tester,
      api,
    ) async {
      api.on('GET /events/evt_1', soldOutDetail());
      api.on('GET /me/event-waitlist', listJson([]));
      await pump(tester, api);
      expect(_cta('Join waitlist'), findsOneWidget);
      expect(
        find.text(
          'No payment now. We will tell you if a ticket becomes available.',
        ),
        findsOneWidget,
      );
      expect(_cta('Sold out'), findsNothing);
      expect(
        EventsAnalytics.debugSink!.where(
          (e) => e.name == 'waitlist_cta_viewed',
        ),
        hasLength(1),
      );
    });

    apiTest('flag off or old server: the plain Sold out stays', (
      tester,
      api,
    ) async {
      api.on('GET /events/evt_1', soldOutDetail());
      await pump(tester, api, options: optsWl(waitlist: false));
      expect(_cta('Sold out'), findsOneWidget);
      expect(_cta('Join waitlist'), findsNothing);
      expect(api.sent('GET', '/me/event-waitlist'), isFalse);
    });

    apiTest('a closed waitlist keeps Sold out', (tester, api) async {
      api.on('GET /events/evt_1', soldOutDetail(state: 'closed'));
      await pump(tester, api);
      expect(_cta('Sold out'), findsOneWidget);
      expect(_cta('Join waitlist'), findsNothing);
    });

    apiTest('already waiting: "On the waitlist" opens the list', (
      tester,
      api,
    ) async {
      api.on('GET /events/evt_1', soldOutDetail());
      api.on('GET /me/event-waitlist', listJson([entryJson()]));
      await pump(tester, api);
      expect(_cta('On the waitlist'), findsOneWidget);
      expect(_cta('Join waitlist'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('event-cta')));
      expect(find.text('ROUTE-WAITLIST'), findsOneWidget);
    });

    apiTest('Join waitlist opens the join page with the one ticket', (
      tester,
      api,
    ) async {
      api.on('GET /events/evt_1', soldOutDetail());
      api.on('GET /me/event-waitlist', listJson([]));
      await pumpPage(
        tester,
        api,
        MemberEventDetailPage(eventId: 'evt_1', options: optsWl()),
        user: member,
        extraRoutes: [
          ..._waitlistRoutes.where(
            (r) => !(r is GoRoute && r.path == AppRoutes.memberEventDetail),
          ),
          GoRoute(
            path: AppRoutes.memberEventDetail,
            builder: (_, s) => Scaffold(body: Text('X${s.uri}')),
            routes: [
              GoRoute(
                path: 'register',
                builder: (_, s) => Scaffold(body: Text('JOIN${s.uri}')),
              ),
            ],
          ),
        ],
        keepRequests: true,
      );
      await tapVisible(tester, find.byKey(const Key('event-cta')));
      expect(
        find.text(
          'JOIN/member/events/evt_1/register?mode=waitlist&ticketTypeId=tt_early',
        ),
        findsOneWidget,
      );
    });

    apiTest('Swahili: the bar is in Swahili', (tester, api) async {
      api.on('GET /events/evt_1', soldOutDetail());
      api.on('GET /me/event-waitlist', listJson([]));
      await pump(tester, api, lang: 'sw');
      expect(find.text('Jiunge na orodha ya kusubiri'), findsOneWidget);
    });
  });

  group('join page', () {
    Future<PageHost> pump(
      WidgetTester tester,
      RecordingApi api, {
      RegistrationSelfProfile profile = _profile,
      String? ticket = 'tt_early',
      String lang = 'en',
    }) => pumpPage(
      tester,
      api,
      MemberEventWaitlistJoinPage(
        eventId: 'evt_1',
        ticketTypeId: ticket,
        options: optsWl(),
        selfProfile: profile,
        now: DateTime.utc(2027, 3, 10, 12),
      ),
      user: member,
      lang: lang,
      size: const Size(375, 1600),
      extraRoutes: _waitlistRoutes,
      keepRequests: true,
    );

    void seed(RecordingApi api) {
      api.on('GET /events/evt_1', soldOutDetail());
      api.on('POST /me/event-orders/quote', quoteJson(valid: false));
      api.on('POST /me/events/evt_1/waitlist', {
        'entry': entryJson(position: 4),
      });
    }

    apiTest('shows rules, price today and no payment step; joins', (
      tester,
      api,
    ) async {
      seed(api);
      await pump(tester, api);
      expect(find.text('Join the waitlist'), findsWidgets);
      expect(find.byKey(const Key('waitlist-ticket-tt_early')), findsOneWidget);
      expect(
        find.textContaining('we hold it for you for 12 hours'),
        findsOneWidget,
      );
      expect(find.text('Price today: TSh 20,000'), findsOneWidget);
      expect(find.text('One ticket per person, for you only.'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
      // Standard (open) is disabled with the reason, not selectable.
      expect(
        find.text('Tickets are available now. Register instead.'),
        findsWidgets,
      );
      final btn = tester.widget<FFButton>(
        find.byKey(const Key('waitlist-join')),
      );
      expect(btn.onPressed, isNull);
      await tapVisible(tester, find.byKey(const Key('waitlist-accept')));
      await tapVisible(tester, find.byKey(const Key('waitlist-join')));
      final req = api.only('POST', '/me/events/evt_1/waitlist');
      final body = req.body as Map;
      expect(body['ticketTypeId'], 'tt_early');
      expect((body['participants'] as List).single['firstName'], 'Amina');
      expect(body['consent'], {
        'accepted': true,
        'textVersion': '2026-10-draft',
      });
      expect(req.headers['idempotency-key'], isNotEmpty);
      expect(find.text("You're on the waitlist"), findsOneWidget);
      expect(find.text('Your number on the list: 4'), findsOneWidget);
      expect(find.text('View my waitlist'), findsOneWidget);
      expect(find.text('Back to event'), findsOneWidget);
      expect(
        EventsAnalytics.debugSink!.map((e) => e.name),
        contains('waitlist_join_started'),
      );
    });

    apiTest('no verified contact: Join stays off and says why', (
      tester,
      api,
    ) async {
      seed(api);
      await pump(
        tester,
        api,
        profile: const RegistrationSelfProfile(
          firstName: 'Amina',
          lastName: 'Mushi',
        ),
      );
      expect(find.byKey(const Key('waitlist-verify')), findsOneWidget);
      expect(
        find.text('Verify your phone number or email to join.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('waitlist-accept')));
      final btn = tester.widget<FFButton>(
        find.byKey(const Key('waitlist-join')),
      );
      expect(btn.onPressed, isNull);
    });

    apiTest('not_sold_out: says so and offers Register', (tester, api) async {
      seed(api);
      api.fail('POST /me/events/evt_1/waitlist', 409, {
        'error': 'not_sold_out',
      });
      await pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('waitlist-accept')));
      await tapVisible(tester, find.byKey(const Key('waitlist-join')));
      expect(
        find.descendant(
          of: find.byKey(const Key('waitlist-refusal')),
          matching: find.text('Tickets are available now. Register instead.'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('waitlist-register-instead')),
        findsOneWidget,
      );
    });

    for (final c in const {
      'already_registered': 'You already have a ticket in this race.',
      'waitlist_full': 'The waitlist is full.',
      'waitlist_limit_reached': 'You are on the most waitlists allowed.',
      'waitlist_lapse_limit':
          "You gave up too many held tickets for this event, so you can't rejoin.",
      'waitlist_unavailable': "The waitlist isn't open right now.",
      'rate_limited': 'Too many tries. Wait a little and try again.',
    }.entries) {
      apiTest('${c.key} shows its own words', (tester, api) async {
        seed(api);
        api.fail(
          'POST /me/events/evt_1/waitlist',
          c.key == 'rate_limited' ? 429 : 409,
          {'error': c.key},
        );
        await pump(tester, api);
        await tapVisible(tester, find.byKey(const Key('waitlist-accept')));
        await tapVisible(tester, find.byKey(const Key('waitlist-join')));
        expect(find.text(c.value), findsOneWidget);
        expect(find.byKey(const Key('waitlist-joined-title')), findsNothing);
      });
    }

    apiTest('a 403 verification_required names the fix', (tester, api) async {
      seed(api);
      api.fail('POST /me/events/evt_1/waitlist', 403, {
        'error': 'verification_required',
      });
      await pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('waitlist-accept')));
      await tapVisible(tester, find.byKey(const Key('waitlist-join')));
      expect(
        find.descendant(
          of: find.byKey(const Key('waitlist-refusal')),
          matching: find.text('Verify your phone number or email to join.'),
        ),
        findsOneWidget,
      );
    });

    apiTest('Swahili join page fits and reads in Swahili', (tester, api) async {
      seed(api);
      await pump(tester, api, lang: 'sw');
      expect(find.text('Jiunge na orodha'), findsNothing);
      expect(find.text('Bei ya leo: TSh 20,000'), findsOneWidget);
      expect(find.textContaining('Kusubiri ni bure.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    apiTest('404 shows the gone state', (tester, api) async {
      api.fail('GET /events/evt_1', 404, {'error': 'event_not_found'});
      await pump(tester, api);
      expect(find.byKey(const Key('waitlist-join-gone')), findsOneWidget);
    });
  });

  group('my waitlist', () {
    Future<PageHost> pump(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
      Size size = const Size(375, 1400),
    }) => pumpPage(
      tester,
      api,
      MemberEventWaitlistPage(
        options: optsWl(),
        now: () => DateTime.utc(2027, 3, 10, 12),
      ),
      user: member,
      lang: lang,
      size: size,
      extraRoutes: _waitlistRoutes,
      keepRequests: true,
    );

    apiTest('waiting card: status chip, number, Leave', (tester, api) async {
      api.on('GET /me/event-waitlist', listJson([entryJson()]));
      await pump(tester, api);
      expect(find.text('Dar Half Marathon'), findsOneWidget);
      expect(find.text('Early bird · 21K Half Marathon'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Your number on the list: 3'), findsOneWidget);
      expect(find.byKey(const Key('waitlist-leave-wl_1')), findsOneWidget);
      expect(find.byKey(const Key('waitlist-pay-wl_1')), findsNothing);
      expect(
        tester
            .getSemantics(find.byKey(const Key('waitlist-position-wl_1')))
            .label,
        contains('Number 3 on the list'),
      );
    });

    apiTest(
      'offer card: deadline in the event zone, Pay now opens the pay page',
      (tester, api) async {
        api.on(
          'GET /me/event-waitlist',
          listJson([
            entryJson(status: 'offered', position: null, offer: _offer),
          ]),
        );
        await pump(tester, api);
        expect(find.text('Ticket held for you'), findsOneWidget);
        // 15:00Z is 18:00 EAT.
        expect(find.textContaining('Pay before'), findsOneWidget);
        expect(find.textContaining('18:00 EAT'), findsOneWidget);
        expect(find.textContaining('min left'), findsOneWidget);
        await tapVisible(tester, find.byKey(const Key('waitlist-pay-wl_1')));
        expect(find.text('ROUTE-PAY-ord_77'), findsOneWidget);
        expect(
          EventsAnalytics.debugSink!.map((e) => e.name),
          contains('waitlist_offer_opened'),
        );
      },
    );

    apiTest('the countdown follows the server clock, not the phone', (
      tester,
      api,
    ) async {
      // serverTime 12:00Z, deadline 15:00Z: 180 minutes, whatever the phone
      // says.
      api.on(
        'GET /me/event-waitlist',
        listJson([entryJson(status: 'offered', position: null, offer: _offer)]),
      );
      await pumpPage(
        tester,
        api,
        MemberEventWaitlistPage(
          options: optsWl(),
          now: () => DateTime.utc(2030, 1, 1),
        ),
        user: member,
        extraRoutes: _waitlistRoutes,
        keepRequests: true,
      );
      expect(find.text('180 min left'), findsOneWidget);
    });

    apiTest('leave asks first, then deletes and reloads', (tester, api) async {
      var calls = 0;
      api.onCall('GET /me/event-waitlist', (_) {
        calls++;
        return calls == 1
            ? listJson([entryJson()])
            : listJson([entryJson(status: 'left', position: null)]);
      });
      api.on('DELETE /me/event-waitlist/wl_1', {
        'entry': entryJson(status: 'left'),
      });
      await pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('waitlist-leave-wl_1')));
      expect(find.text('Leave the waitlist?'), findsOneWidget);
      expect(
        find.text(
          'You will lose your number on the list. You can join again, at the end.',
        ),
        findsOneWidget,
      );
      await tapVisible(
        tester,
        find.byKey(const Key('waitlist-leave-confirm-wl_1')),
      );
      expect(api.sent('DELETE', '/me/event-waitlist/wl_1'), isTrue);
      expect(
        api
            .where('DELETE', '/me/event-waitlist/wl_1')
            .single
            .headers['idempotency-key'],
        isNotEmpty,
      );
      expect(find.text('You left the list'), findsOneWidget);
      expect(find.byKey(const Key('waitlist-leave-wl_1')), findsNothing);
    });

    apiTest('leaving an offered ticket says it gives the ticket up', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-waitlist',
        listJson([entryJson(status: 'offered', position: null, offer: _offer)]),
      );
      await pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('waitlist-leave-wl_1')));
      expect(
        find.text('This gives up your held ticket. Nothing has been charged.'),
        findsOneWidget,
      );
    });

    apiTest('payment_pending on leave says to cancel the order', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-waitlist',
        listJson([entryJson(status: 'offered', position: null, offer: _offer)]),
      );
      api.fail('DELETE /me/event-waitlist/wl_1', 409, {
        'error': 'payment_pending',
      });
      await pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('waitlist-leave-wl_1')));
      await tapVisible(
        tester,
        find.byKey(const Key('waitlist-leave-confirm-wl_1')),
      );
      expect(
        find.text(
          'A payment is waiting for confirmation. Cancel the order instead.',
        ),
        findsOneWidget,
      );
    });

    apiTest('reconsent: banner, Review terms, reconfirm call', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-waitlist',
        listJson([entryJson(blockedReason: 'reconsent')]),
      );
      api.on('POST /me/event-waitlist/wl_1/reconfirm', {'entry': entryJson()});
      await pump(tester, api);
      expect(
        find.text('The terms changed. Review them to stay on the list.'),
        findsOneWidget,
      );
      await tapVisible(
        tester,
        find.byKey(const Key('waitlist-reconfirm-wl_1')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('waitlist-reconfirm-confirm-wl_1')),
      );
      final req = api.only('POST', '/me/event-waitlist/wl_1/reconfirm');
      expect((req.body as Map)['consent'], {
        'accepted': true,
        'textVersion': '2026-10-draft',
      });
    });

    apiTest('ended entries show the reason and no Leave', (tester, api) async {
      api.on(
        'GET /me/event-waitlist',
        listJson([
          entryJson(
            status: 'closed',
            position: null,
            endedReason: 'organizer_closed',
          ),
        ]),
      );
      await pump(tester, api);
      expect(find.text('Waitlist closed'), findsOneWidget);
      expect(find.text('The organizer closed the waitlist.'), findsOneWidget);
      expect(find.byKey(const Key('waitlist-leave-wl_1')), findsNothing);
    });

    apiTest('empty state links to Events', (tester, api) async {
      api.on('GET /me/event-waitlist', listJson([]));
      await pump(tester, api);
      expect(find.text("You're not on any waitlist."), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('waitlist-browse')));
      expect(find.text('ROUTE-EVENTS'), findsOneWidget);
    });

    apiTest('offline: the saved copy shows and leave needs a connection', (
      tester,
      api,
    ) async {
      // A good load was saved earlier; then the network goes.
      await EventsCache.putMine('waitlist', listJson([entryJson()]));
      api.onCall(
        'GET /me/event-waitlist',
        (_) => throw StateError('SocketException: offline'),
      );
      await pump(tester, api);
      expect(find.byKey(const Key('waitlist-offline')), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('waitlist-leave-wl_1')));
      expect(
        find.text('No internet. You need a connection to join or leave.'),
        findsOneWidget,
      );
      expect(api.sent('DELETE', '/me/event-waitlist/wl_1'), isFalse);
    });

    apiTest('error with nothing saved: retry state', (tester, api) async {
      api.fail('GET /me/event-waitlist', 500);
      await pump(tester, api);
      expect(find.byKey(const Key('waitlist-error')), findsOneWidget);
    });

    apiTest('desktop width lays cards in two columns, Swahili fits', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-waitlist',
        listJson([
          entryJson(),
          entryJson(
            id: 'wl_2',
            status: 'offered',
            position: null,
            offer: _offer,
          ),
        ]),
      );
      await pump(tester, api, lang: 'sw', size: const Size(1000, 900));
      final a = tester.getTopLeft(find.byKey(const Key('waitlist-card-wl_1')));
      final b = tester.getTopLeft(find.byKey(const Key('waitlist-card-wl_2')));
      expect(a.dy, b.dy);
      expect(a.dx, isNot(b.dx));
      expect(find.text('Inasubiri'), findsOneWidget);
      expect(find.text('Tiketi imeshikiliwa kwa ajili yako'), findsWidgets);
      expect(find.text('Lipa sasa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    apiTest('the Mine page gets a Waitlist tab only when the flag is on', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations', page([]));
      api.on('GET /me/event-registrations/claimable', {'items': []});
      api.on('GET /me/event-orders', page([]));
      api.on('GET /me/event-waitlist', listJson([entryJson()]));
      await pumpPage(
        tester,
        api,
        MemberEventOrdersPage(initialTab: 'waitlist', options: optsWl()),
        user: member,
        size: const Size(375, 1400),
        extraRoutes: _waitlistRoutes,
        keepRequests: true,
      );
      expect(find.text('Waitlist'), findsWidgets);
      expect(find.byKey(const Key('waitlist-card-wl_1')), findsOneWidget);
    });

    apiTest('flag off: no Waitlist tab and no waitlist request', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations', page([]));
      api.on('GET /me/event-registrations/claimable', {'items': []});
      api.on('GET /me/event-orders', page([]));
      await pumpPage(
        tester,
        api,
        MemberEventOrdersPage(options: optsWl(waitlist: false)),
        user: member,
        size: const Size(375, 1400),
        extraRoutes: _waitlistRoutes,
        keepRequests: true,
      );
      expect(find.text('Waitlist'), findsNothing);
      expect(api.sent('GET', '/me/event-waitlist'), isFalse);
    });
  });

  group('waitlist order', () {
    Future<PageHost> pump(WidgetTester tester, RecordingApi api) => pumpPage(
      tester,
      api,
      MemberEventOrderPage(
        orderId: 'ord_77',
        options: optsWl(),
        now: DateTime.utc(2027, 3, 10, 12),
      ),
      user: member,
      size: const Size(375, 1800),
      extraRoutes: _waitlistRoutes,
      keepRequests: true,
    );

    Map<String, dynamic> fromWaitlist(Map<String, dynamic> o) => {
      ...o,
      'order': {...(o['order'] as Map<String, dynamic>), 'source': 'waitlist'},
    };

    apiTest('a held waitlist order carries the chip', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_77',
        fromWaitlist(orderJson(id: 'ord_77')),
      );
      await pump(tester, api);
      expect(find.byKey(const Key('order-waitlist-chip')), findsOneWidget);
      expect(find.text('From the waitlist'), findsOneWidget);
      expect(find.byKey(const Key('order-waitlist-passed')), findsNothing);
      expect(
        EventsAnalytics.debugSink!.where(
          (e) => e.name == 'waitlist_offer_opened',
        ),
        hasLength(1),
      );
    });

    apiTest('an expired waitlist order says the turn passed and refunds', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_77',
        fromWaitlist(
          orderJson(id: 'ord_77', status: 'expired', holdExpiresAt: null),
        ),
      );
      await pump(tester, api);
      expect(find.byKey(const Key('order-expired')), findsOneWidget);
      expect(
        find.text('Your turn passed. If you already paid, we will refund you.'),
        findsOneWidget,
      );
    });

    apiTest('a normal order has neither', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', orderJson());
      await pumpPage(
        tester,
        api,
        MemberEventOrderPage(orderId: 'ord_1', options: optsWl()),
        user: member,
        size: const Size(375, 1800),
        extraRoutes: _waitlistRoutes,
      );
      expect(find.byKey(const Key('order-waitlist-chip')), findsNothing);
    });
  });
}
