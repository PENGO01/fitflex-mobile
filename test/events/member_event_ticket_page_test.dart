// Events S4 (spec §5.5, §5.8 member_event_ticket_page_test): the QR drawn
// from the server's payload with the number, participant, category and
// state as text; the kit-scanning wording by `scanning`; a revoked ticket
// draws no QR; claimed elsewhere; rotate; the on-device copy (write, read,
// delete on sign-out / revoked / claimed elsewhere / 30 days after).
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/events/tickets/member_event_ticket_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/event_ticket.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

const _token = 'ev1.k1.etk_reg_1.1.AAAAAAAAAAAAAAAAAAAAAA';
const _token2 = 'ev1.k1.etk_reg_1.2.BBBBBBBBBBBBBBBBBBBBBB';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  EventsOptions? options,
  String lang = 'en',
  Size size = const Size(375, 1800),
}) => pumpPage(
  tester,
  api,
  MemberEventTicketPage(
    registrationId: 'reg_1',
    options: options ?? optsS3(payment: 'manual', ticketsQr: true),
  ),
  user: member,
  lang: lang,
  size: size,
  extraRoutes: s3Routes,
  keepRequests: true,
);

String _drawn(WidgetTester tester) =>
    tester.widget<FFQrCode>(find.byKey(const Key('ticket-qr'))).data;

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
    EventTicketCache.clock = DateTime.now;
  });

  apiTest('draws the server payload; the facts are text too', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
    final host = await _pump(tester, api);
    expect(_drawn(tester), 'FFEV1:$_token');
    expect(find.text('Dar Half Marathon'), findsOneWidget);
    expect(find.byKey(const Key('ticket-participant')), findsOneWidget);
    expect(find.text('Asha Mollel'), findsOneWidget);
    expect(find.text('21K Half Marathon · Standard'), findsOneWidget);
    expect(find.text('Ticket number T-3F9A2B'), findsOneWidget);
    expect(find.text('Ticket ready'), findsOneWidget);
    // The painted code has a text alternative, the picture itself is hidden.
    final label = host
        .tr('events.ticket.qr.a11y')
        .replaceFirst('{name}', 'Asha Mollel')
        .replaceFirst('{category}', '21K Half Marathon')
        .replaceFirst('{code}', 'T-3F9A2B');
    expect(find.bySemanticsLabel(label), findsOneWidget);
    // Copy has a tooltip; there is no share action.
    expect(find.byTooltip('Copy ticket number'), findsOneWidget);
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.textContaining('Share'), findsNothing);
    expect(EventsAnalytics.debugSink!.single.name, 'ticket_opened');
    // The registration id is only the page's; the server counts per event
    // (S7 contract), and the transport drops the registration id.
    expect(EventsAnalytics.debugSink!.single.props, {
      'registrationId': 'reg_1',
      'eventId': 'evt_1',
    });
  });

  apiTest('the code is at least 240 dp on a phone, on white, dark ink', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
    await _pump(tester, api);
    final size = tester.getSize(find.byKey(const Key('ticket-qr')));
    expect(size.width, greaterThanOrEqualTo(240));
    expect(size.width, lessThanOrEqualTo(320));
    final card = tester.widget<Container>(
      find.byKey(const Key('ticket-qr-card')),
    );
    expect(card.color, const Color(0xFFFFFFFF));
  });

  group('kit scanning wording', () {
    apiTest('not live: says so and promises nothing about entry', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      await _pump(tester, api);
      expect(
        find.text(
          "Kit collection scanning isn't live yet. Keep this code; the "
          'organizer will confirm where and when to collect your kit.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('entry'), findsNothing);
      expect(find.textContaining('screenshot'), findsNothing);
    });

    apiTest('live from the payload', (tester, api) async {
      api.on(
        'GET /me/event-registrations/reg_1/ticket',
        ticketPayload(scanning: true),
      );
      await _pump(tester, api);
      expect(
        find.text('Show this code at the kit collection point.'),
        findsOneWidget,
      );
    });

    apiTest('live from the options even with a stale payload', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      await _pump(
        tester,
        api,
        options: optsS3(payment: 'manual', ticketsQr: true, scanning: true),
      );
      expect(
        find.text('Show this code at the kit collection point.'),
        findsOneWidget,
      );
    });
  });

  apiTest('bought for someone else: you can see it until they claim', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1/ticket',
      ticketPayload(relation: 'purchased', first: 'Juma'),
    );
    await _pump(tester, api);
    expect(
      find.text('You can see this ticket until Juma claims it.'),
      findsOneWidget,
    );
  });

  group('revoked', () {
    for (final reason in ['cancelled', 'event_cancelled', 'refunded']) {
      apiTest('$reason draws no QR and says why', (tester, api) async {
        await EventTicketCache.put('reg_1', ticketPayload());
        api.fail('GET /me/event-registrations/reg_1/ticket', 409, {
          'error': 'ticket_revoked',
          'reason': reason,
        });
        final host = await _pump(tester, api);
        expect(find.byType(FFQrCode), findsNothing);
        expect(find.byKey(const Key('ticket-qr')), findsNothing);
        expect(
          find.text(host.tr('events.ticket.revoked.$reason')),
          findsOneWidget,
        );
        expect(find.text('This code no longer works.'), findsOneWidget);
        // The saved copy of a dead ticket is deleted.
        expect(await EventTicketCache.get('reg_1'), isNull);
      });
    }
  });

  apiTest('claimed elsewhere: explained, and the saved copy is deleted', (
    tester,
    api,
  ) async {
    await EventTicketCache.put('reg_1', ticketPayload(first: 'Juma'));
    api.fail('GET /me/event-registrations/reg_1/ticket', 404, {
      'error': 'registration_not_found',
    });
    await _pump(tester, api);
    expect(find.byType(FFQrCode), findsNothing);
    expect(
      find.text('Juma claimed this ticket. It is now in their app.'),
      findsOneWidget,
    );
    expect(await EventTicketCache.get('reg_1'), isNull);
  });

  apiTest('not issued yet hands over to the registration page', (
    tester,
    api,
  ) async {
    api.fail('GET /me/event-registrations/reg_1/ticket', 409, {
      'error': 'ticket_not_issued',
    });
    await _pump(tester, api);
    expect(find.text('ROUTE-REG-reg_1'), findsOneWidget);
    expect(find.byType(FFQrCode), findsNothing);
  });

  group('get a new code', () {
    apiTest('confirms, rotates, re-renders and replaces the saved copy', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      api.on(
        'POST /me/event-registrations/reg_1/ticket/rotate',
        ticketPayload(token: _token2),
      );
      final host = await _pump(tester, api);
      expect(_drawn(tester), 'FFEV1:$_token');
      await tapVisible(tester, find.byKey(const Key('ticket-rotate')));
      expect(find.text('Get a new code?'), findsOneWidget);
      expect(
        find.textContaining(
          'The old code stops working, including any screenshot',
        ),
        findsOneWidget,
      );
      // Cancelling does nothing.
      await tapVisible(tester, find.byKey(const Key('ticket-rotate-cancel')));
      expect(
        api.sent('POST', '/me/event-registrations/reg_1/ticket/rotate'),
        isFalse,
      );
      await tapVisible(tester, find.byKey(const Key('ticket-rotate')));
      await tapVisible(tester, find.byKey(const Key('ticket-rotate-confirm')));
      expect(
        api.only('POST', '/me/event-registrations/reg_1/ticket/rotate'),
        isNotNull,
      );
      expect(_drawn(tester), 'FFEV1:$_token2');
      expect(host.snack('New code ready'), findsOneWidget);
      // The old code is gone from this phone too.
      final saved = await EventTicketCache.get('reg_1');
      expect(saved!.ticket.token, _token2);
      expect(EventsAnalytics.debugSink!.map((e) => e.name), [
        'ticket_opened',
        'ticket_rotated',
      ]);
    });

    apiTest('a rotation that finds the ticket revoked shows the revoked view', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      api.fail('POST /me/event-registrations/reg_1/ticket/rotate', 409, {
        'error': 'ticket_revoked',
        'reason': 'cancelled',
      });
      await _pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('ticket-rotate')));
      await tapVisible(tester, find.byKey(const Key('ticket-rotate-confirm')));
      expect(find.byType(FFQrCode), findsNothing);
      expect(find.byKey(const Key('ticket-revoked')), findsOneWidget);
    });

    apiTest('a rate limit is a snack with the reason', (tester, api) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      api.fail('POST /me/event-registrations/reg_1/ticket/rotate', 429, {
        'error': 'rate_limited',
        'retryAfterSeconds': 3600,
      });
      final host = await _pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('ticket-rotate')));
      await tapVisible(tester, find.byKey(const Key('ticket-rotate-confirm')));
      expect(_drawn(tester), 'FFEV1:$_token');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(host.snack('New code ready'), findsNothing);
    });
  });

  group('offline and the saved copy', () {
    apiTest('every good read is saved on this phone', (tester, api) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      await _pump(tester, api);
      final saved = await EventTicketCache.get('reg_1');
      expect(saved, isNotNull);
      expect(saved!.ticket.qrPayload, 'FFEV1:$_token');
    });

    apiTest('offline with a copy: the saved code, the chip and the notice', (
      tester,
      api,
    ) async {
      await EventTicketCache.put('reg_1', ticketPayload());
      api.onCall(
        'GET /me/event-registrations/reg_1/ticket',
        (_) => throw StateError('SocketException: down'),
      );
      await _pump(tester, api);
      expect(_drawn(tester), 'FFEV1:$_token');
      expect(find.byKey(const Key('ticket-cached')), findsOneWidget);
      expect(
        find.textContaining('Saved on this phone · updated'),
        findsOneWidget,
      );
      expect(
        find.text("You're offline. Showing the saved code."),
        findsOneWidget,
      );
      // A new code needs the network.
      expect(
        isEnabled(tester, find.byKey(const Key('ticket-rotate'))),
        isFalse,
      );
    });

    apiTest('offline with no copy: an error state', (tester, api) async {
      api.onCall(
        'GET /me/event-registrations/reg_1/ticket',
        (_) => throw StateError('SocketException: down'),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('ticket-error')), findsOneWidget);
      expect(find.byType(FFQrCode), findsNothing);
    });

    apiTest('a copy is deleted 30 days after the event', (tester, api) async {
      final starts = DateTime.utc(2027, 3, 14, 3, 30);
      EventTicketCache.clock = () => DateTime.utc(2027, 3, 10);
      await EventTicketCache.put(
        'reg_1',
        ticketPayload(),
        eventStartsAt: starts,
      );
      EventTicketCache.clock = () => DateTime.utc(2027, 4, 10);
      expect(await EventTicketCache.get('reg_1'), isNotNull);
      EventTicketCache.clock = () => DateTime.utc(2027, 4, 14);
      expect(await EventTicketCache.get('reg_1'), isNull);
      // And it is gone for good.
      EventTicketCache.clock = () => DateTime.utc(2027, 3, 11);
      expect(await EventTicketCache.get('reg_1'), isNull);
    });

    apiTest('sign-out removes every saved ticket', (tester, api) async {
      await EventTicketCache.put('reg_1', ticketPayload());
      await EventTicketCache.put(
        'reg_2',
        ticketPayload(registrationId: 'reg_2'),
      );
      await _pump(tester, api); // signed in as a member
      final auth = AppScope.of(
        tester.element(find.byType(Scaffold).first),
      ).auth;
      await auth.signOut();
      expect(await EventTicketCache.get('reg_1'), isNull);
      expect(await EventTicketCache.get('reg_2'), isNull);
    });
  });

  apiTest('a failed read with a server error is an error state with retry', (
    tester,
    api,
  ) async {
    api.fail('GET /me/event-registrations/reg_1/ticket', 500);
    await _pump(tester, api);
    expect(find.byKey(const Key('ticket-error')), findsOneWidget);
    api.heal('GET /me/event-registrations/reg_1/ticket');
    api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
    await tapVisible(tester, find.text('Try again').first);
    expect(_drawn(tester), 'FFEV1:$_token');
  });

  apiTest('wide layout keeps the code at most 320 dp', (tester, api) async {
    api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
    await _pump(tester, api, size: const Size(1280, 800));
    expect(tester.getSize(find.byKey(const Key('ticket-qr'))).width, 320);
  });

  apiTest('Swahili: the wording and the number', (tester, api) async {
    api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
    await _pump(tester, api, lang: 'sw');
    expect(find.text('Namba ya tiketi T-3F9A2B'), findsOneWidget);
    expect(find.text('Tiketi iko tayari'), findsOneWidget);
    expect(
      find.textContaining('Skani ya kuchukua vifaa vya mbio'),
      findsOneWidget,
    );
    expect(find.text('Pata msimbo mpya'), findsOneWidget);
  });
}
