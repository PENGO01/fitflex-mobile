// Events S7 (spec §5.4, §13 AC-N1, AC-N3): the analytics transport. Off by
// default and with an older server; never carries ids, amounts or names;
// buckets counts; holds at most 100 events in memory only; flushes at 10, in
// batches of 20, with one retry; drops events recorded offline; never blocks.
// Plus the offline ticket checks the spec asks for (QR shown offline with the
// saved-copy line, kit hint).
import 'dart:convert';

import 'package:fitflexmobile/screens/member/events/tickets/member_event_ticket_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/event_ticket.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_analytics_transport.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

const _token = 'ev1.k1.etk_reg_1.1.AAAAAAAAAAAAAAAAAAAAAA';

/// Everything a screen might hand over, with the values that must never leave
/// the phone.
const _sensitive = {
  'orderId': 'ord_secret',
  'registrationId': 'reg_secret',
  'totalTzs': 123456,
  'placesCount': 7,
  'name': 'Amina Mushi',
  'phone': '+255712345678',
  'bib': '1042',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sent = <List<Map<String, dynamic>>>[];
  late EventsAnalyticsTransport t;

  setUp(() {
    sent.clear();
    t = EventsAnalyticsTransport.instance..reset();
    t.platform = () => 'android';
    EventsAnalytics.debugSink = null;
  });
  tearDown(() {
    t.reset();
    EventsAnalytics.debugSink = null;
  });

  Future<void> ok(List<Map<String, dynamic>> events) async =>
      sent.add(List.of(events));

  group('wire form', () {
    test('drops ids, amounts and names; keeps buckets and platform', () {
      final w = analyticsWire('checkout_quote_created', {
        ..._sensitive,
        'eventId': 'evt_1',
        'placesCount': 3,
        'totalTzs': 50000,
        'mode': 'self',
      }, platform: 'ios')!;
      expect(w['name'], 'checkout_quote_created');
      expect(w['props'], {
        'eventId': 'evt_1',
        'places': 3,
        'mode': 'self',
        'platform': 'ios',
      });
      final text = jsonEncode(w);
      for (final v in _sensitive.values) {
        // The sensitive values are gone (places is the small count 3).
        expect(text, isNot(contains('$v')));
      }
    });

    test('small counts go raw; the server buckets (contract C)', () {
      final w = analyticsWire('event_list_viewed', {
        'filtersActive': 3,
        'resultCount': 12,
      }, platform: 'web')!;
      expect(w['props'], {'filters': 3, 'results': 12, 'platform': 'web'});
      final q = analyticsWire('checkout_quote_created', {
        'placesCount': 0,
      }, platform: 'web')!;
      expect((q['props'] as Map)['places'], 0);
      // A huge or negative or non-number count is capped or dropped.
      final big = analyticsWire('event_list_viewed', {
        'filtersActive': 5000000,
        'resultCount': -2,
      }, platform: 'web')!;
      expect(big['props'], {'filters': maxRawCount, 'platform': 'web'});
      final text = analyticsWire('event_list_viewed', {
        'filtersActive': '2+',
        'resultCount': '1-5',
      }, platform: 'web')!;
      expect(text['props'], {'platform': 'web'});
    });

    test('names the server writes itself are never sent', () {
      for (final n in serverOnlyEvents) {
        expect(analyticsWire(n, {'orderId': 'x'}, platform: 'web'), isNull);
      }
      expect(analyticsWire('made_up', {}, platform: 'web'), isNull);
    });

    test('values outside a closed set are dropped, not forwarded', () {
      final w = analyticsWire('event_detail_viewed', {
        'eventId': 'evt_1',
        'availability': 'something else',
      }, platform: 'web')!;
      expect(w['props'], {'eventId': 'evt_1', 'platform': 'web'});
      // An id with spaces or symbols is not an id.
      final bad = analyticsWire('event_saved', {
        'eventId': 'Amina Mushi <script>',
        'saved': true,
      }, platform: 'web')!;
      expect(bad['props'], {'saved': true, 'platform': 'web'});
    });

    test('payment states fold into the closed set; mode becomes method', () {
      String state(String s) =>
          (analyticsWire('payment_state_seen', {
                    'state': s,
                  }, platform: 'web')!['props']
                  as Map)['state']
              as String;
      expect(state('submitted'), 'pending');
      expect(state('processing'), 'pending');
      expect(state('confirmed'), 'confirmed');
      expect(state('failed'), 'rejected');
      expect(state('needs_attention'), 'unknown');
      final p =
          analyticsWire('payment_started', {
                'orderId': 'o',
                'mode': 'provider',
                'late': false,
                'eventId': 'evt_1',
              }, platform: 'web')!['props']
              as Map;
      expect(p, {
        'method': 'mobile_money',
        'late': false,
        'eventId': 'evt_1',
        'platform': 'web',
      });
    });

    test('never more than 8 props', () {
      for (final n in [
        'checkout_quote_created',
        'payment_started',
        'event_detail_viewed',
      ]) {
        final w = analyticsWire(n, {
          for (var i = 0; i < 30; i++) 'k$i': 'v',
          'eventId': 'e',
        }, platform: 'web')!;
        expect((w['props'] as Map).length, lessThanOrEqualTo(8));
      }
    });
  });

  group('transport', () {
    test('off by default: nothing is queued or sent (AC-N1)', () async {
      EventsAnalytics.detailViewed(eventId: 'evt_1', availability: 'open');
      EventsAnalytics.waitlistCtaViewed(eventId: 'evt_1');
      expect(t.enabled, isFalse);
      expect(t.queued, 0);
      await t.flush();
      expect(sent, isEmpty);
    });

    test('on: calls queue, flush sends one batch with the platform', () async {
      t.configure(enabled: true, send: ok);
      EventsAnalytics.detailViewed(eventId: 'evt_1', availability: 'sold_out');
      EventsAnalytics.saved(eventId: 'evt_1', saved: true);
      expect(t.queued, 2);
      await t.flush();
      expect(t.queued, 0);
      expect(sent, hasLength(1));
      expect(sent.single.map((e) => e['name']), [
        'event_detail_viewed',
        'event_saved',
      ]);
      expect((sent.single.first['props'] as Map)['platform'], 'android');
    });

    test('flushes by itself at 10 queued', () async {
      t.configure(enabled: true, send: ok);
      for (var i = 0; i < 9; i++) {
        EventsAnalytics.ticketRotated(eventId: 'evt_1');
      }
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
      EventsAnalytics.ticketRotated(eventId: 'evt_1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent.expand((b) => b), hasLength(10));
    });

    test('a request carries at most 20 events', () async {
      t.configure(enabled: true, send: ok);
      // Fill without flushing (the 10-queued flush is held by the first send).
      for (var i = 0; i < 45; i++) {
        EventsAnalytics.ticketRotated(eventId: 'evt_1');
      }
      await t.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent.expand((b) => b), hasLength(45));
      expect(sent.every((b) => b.length <= 20), isTrue);
    });

    test('keeps at most 100 in memory, oldest dropped', () async {
      var gate = false;
      t.configure(
        enabled: true,
        send: (e) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (gate) sent.add(e);
        },
      );
      for (var i = 0; i < 250; i++) {
        EventsAnalytics.ticketRotated(eventId: 'evt_$i');
      }
      expect(t.queued, lessThanOrEqualTo(EventsAnalyticsTransport.maxQueued));
      gate = true;
      // Let the flush that started at 10 queued finish before the next test.
      t.reset();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });

    test('one retry on a server error, then dropped', () async {
      var calls = 0;
      t.configure(
        enabled: true,
        send: (e) async {
          calls++;
          throw ApiException(500, 'failed');
        },
      );
      EventsAnalytics.ticketRotated(eventId: 'evt_1');
      await t.flush();
      expect(calls, 2);
      expect(t.queued, 0);
    });

    test('offline: dropped at once, never kept for later', () async {
      var calls = 0;
      t.configure(
        enabled: true,
        send: (e) async {
          calls++;
          throw StateError('SocketException: offline');
        },
      );
      EventsAnalytics.ticketRotated(eventId: 'evt_1');
      await t.flush();
      expect(calls, 1);
      expect(t.queued, 0);
      await t.flush();
      expect(calls, 1);
    });

    test('a failing sender never throws into the screen', () async {
      t.configure(enabled: true, send: (e) async => throw Exception('boom'));
      expect(
        () => EventsAnalytics.detailViewed(eventId: 'e', availability: 'open'),
        returnsNormally,
      );
      await t.flush();
    });

    test('switching off or signing out empties the queue', () async {
      t.configure(enabled: true, send: ok);
      EventsAnalytics.ticketRotated(eventId: 'evt_1');
      expect(t.queued, 1);
      t.configure(enabled: false, send: ok);
      expect(t.queued, 0);
      expect(t.enabled, isFalse);
      t.configure(enabled: true, send: ok);
      EventsAnalytics.ticketRotated(eventId: 'evt_1');
      await EventsCache.clearAll();
      expect(t.queued, 0);
      expect(t.enabled, isFalse);
    });

    test('nothing is written to the phone', () async {
      SharedPreferences.setMockInitialValues({});
      t.configure(enabled: true, send: ok);
      EventsAnalytics.detailViewed(eventId: 'evt_1', availability: 'open');
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), isEmpty);
    });

    test('the debug sink still sees the raw call (old tests stay valid)', () {
      EventsAnalytics.debugSink = [];
      EventsAnalytics.orderCreated(
        orderId: 'o1',
        eventId: 'evt_1',
        placesCount: 2,
        totalTzs: 10,
        mode: 'self',
        team: false,
      );
      expect(EventsAnalytics.debugSink!.single.name, 'order_created');
      // ...but the server-only name never reaches the transport.
      expect(t.queued, 0);
    });

    test('the new calls are named as the spec says', () {
      EventsAnalytics.debugSink = [];
      EventsAnalytics.waitlistCtaViewed(eventId: 'e');
      EventsAnalytics.waitlistJoinStarted(eventId: 'e');
      EventsAnalytics.waitlistOfferOpened(eventId: 'e');
      EventsAnalytics.runStarted(eventId: 'e');
      expect(EventsAnalytics.debugSink!.map((x) => x.name), [
        'waitlist_cta_viewed',
        'waitlist_join_started',
        'waitlist_offer_opened',
        'run_started',
      ]);
    });
  });

  test('the privacy sentence exists in both languages', () {
    expect(
      FFLocale.textOf('en', 'events.privacy.analytics'),
      'We count how the events screens are used, without your name or account.',
    );
    expect(FFLocale.textOf('sw', 'events.privacy.analytics'), isNotEmpty);
  });

  group('offline ticket (spec §5.4)', () {
    setUp(() {
      debugEventsDiscoveryOverride = true;
      EventTicketCache.clock = DateTime.now;
    });
    tearDown(() {
      debugEventsDiscoveryOverride = null;
      EventTicketCache.clock = DateTime.now;
    });

    Future<PageHost> pump(WidgetTester tester, RecordingApi api) => pumpPage(
      tester,
      api,
      MemberEventTicketPage(
        registrationId: 'reg_1',
        options: optsS3(payment: 'manual', ticketsQr: true),
      ),
      user: member,
      size: const Size(375, 1800),
      extraRoutes: s3Routes,
      keepRequests: true,
    );

    apiTest(
      'saved over five minutes ago: the QR shows with the saved-copy line and '
      'the kit status may be old',
      (tester, api) async {
        final saved = DateTime.now().subtract(const Duration(minutes: 10));
        EventTicketCache.clock = () => saved;
        await EventTicketCache.put(
          'reg_1',
          ticketPayload(scanning: true, kit: {'state': 'ready'}),
        );
        EventTicketCache.clock = DateTime.now;
        api.onCall(
          '/me/event-registrations/reg_1/ticket',
          (_) => throw StateError('SocketException: down'),
        );
        api.onCall(
          'GET /me/event-registrations/reg_1/ticket',
          (_) => throw StateError('SocketException: down'),
        );
        await pump(tester, api);
        expect(
          tester.widget<FFQrCode>(find.byKey(const Key('ticket-qr'))).data,
          'FFEV1:$_token',
        );
        expect(
          find.textContaining('Saved on this phone · updated'),
          findsOneWidget,
        );
        expect(
          find.text("You're offline. Showing the saved code."),
          findsOneWidget,
        );
        expect(
          find.text('Kit status may have changed. Connect to refresh.'),
          findsOneWidget,
        );
      },
    );
  });
}
