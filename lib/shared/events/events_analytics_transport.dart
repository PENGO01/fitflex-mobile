// Events S7 (docs/design/events-s7-hardening-and-pilot.md §5.4): the one
// transport behind `EventsAnalytics`. It only counts how the events screens
// are used. Rules: an allowlist per event (anything else is dropped), counts
// turned into buckets, no order or registration ids, no amounts, no names;
// at most 100 events held, in memory only; flushed every 30 seconds, at 10
// queued and when the app is paused; one retry, then dropped; never sent
// offline; never blocks a screen; payloads are never logged.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api_client.dart';
import '../api_error_message.dart';
import 'events_cache.dart';

typedef AnalyticsSender =
    Future<void> Function(List<Map<String, dynamic>> events);

/// What the transport may send for one event name: the closed value sets, or
/// null for a free `eventId`.
const Map<String, Map<String, Set<String>?>> _allowlist = {
  'event_list_viewed': {
    'filters': {'0', '1', '2+'},
    'results': {'0', '1-5', '6-20', '21+'},
  },
  'event_detail_viewed': {
    'availability': {
      'open',
      'closing_soon',
      'sold_out',
      'closed',
      'not_yet_open',
      'cancelled',
      'in_progress',
      'completed',
    },
    'eventId': null,
  },
  'event_saved': {
    'saved': {'true', 'false'},
    'eventId': null,
  },
  'registration_started': {
    'source': {'cta', 'ticket_row', 'deep_link', 'other'},
    'eventId': null,
  },
  'checkout_quote_created': {
    'mode': {'self', 'others', 'group', 'team'},
    'eventId': null,
    'places': {'1', '2-5', '6+'},
  },
  'payment_started': {
    'late': {'true', 'false'},
    'method': {'manual', 'mobile_money'},
  },
  'payment_submitted': {
    'late': {'true', 'false'},
    'method': {'manual', 'mobile_money'},
  },
  'payment_state_seen': {
    'state': {
      'pending',
      'confirmed',
      'rejected',
      'expired',
      'unknown',
      'refunded',
    },
    'method': {'manual', 'mobile_money'},
  },
  'ticket_opened': {},
  'ticket_rotated': {},
  'invitation_resent': {},
  'cancel_preview_viewed': {
    'scope': {'place', 'order'},
    'mode': {'policy', 'none', 'full', 'other'},
  },
  'cancel_confirmed': {
    'scope': {'place', 'order'},
    'mode': {'policy', 'none', 'full', 'other'},
  },
  'run_started': {'eventId': null},
  'waitlist_cta_viewed': {'eventId': null},
  'waitlist_join_started': {'eventId': null},
  'waitlist_offer_opened': {'eventId': null},
};

/// Names the server writes itself; the app never sends them so nothing is
/// counted twice (spec §5.1).
const Set<String> serverOnlyEvents = {
  'order_created',
  'order_cancelled',
  'registration_claimed',
};

String bucketFilters(int n) => n <= 0 ? '0' : (n == 1 ? '1' : '2+');

String bucketResults(int n) => n <= 0
    ? '0'
    : n <= 5
    ? '1-5'
    : n <= 20
    ? '6-20'
    : '21+';

String bucketPlaces(int n) => n <= 1 ? '1' : (n <= 5 ? '2-5' : '6+');

/// The wire form of one call, or null when it must not be sent (an unknown
/// name, or one the server emits itself). Unknown keys and values outside the
/// closed sets are dropped, never forwarded.
Map<String, dynamic>? analyticsWire(
  String name,
  Map<String, Object?> raw, {
  required String platform,
}) {
  if (serverOnlyEvents.contains(name)) return null;
  final allowed = _allowlist[name];
  if (allowed == null) return null;
  final src = <String, Object?>{...raw};
  // Raw counts become buckets; amounts and order ids are never read.
  if (name == 'event_list_viewed') {
    src['filters'] = bucketFilters((raw['filtersActive'] as int?) ?? 0);
    src['results'] = bucketResults((raw['resultCount'] as int?) ?? 0);
  }
  if (name == 'checkout_quote_created') {
    src['places'] = bucketPlaces((raw['placesCount'] as int?) ?? 1);
  }
  if (name == 'payment_started') {
    src['method'] = _method(raw['mode']);
  }
  if (name == 'payment_state_seen') {
    // The app's payment states folded into the closed set the server counts.
    src['state'] = switch (raw['state']?.toString()) {
      'submitted' || 'processing' || 'none' => 'pending',
      'confirmed' => 'confirmed',
      'rejected' || 'failed' => 'rejected',
      'expired' => 'expired',
      'refunded' => 'refunded',
      _ => 'unknown',
    };
  }
  final props = <String, Object?>{};
  for (final e in allowed.entries) {
    final v = src[e.key];
    if (v == null) continue;
    final text = v.toString();
    if (e.value == null) {
      // A free id: short and plain, nothing else.
      if (RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(text)) {
        props[e.key] = text;
      }
    } else if (e.value!.contains(text)) {
      props[e.key] = e.key == 'late' || e.key == 'saved'
          ? text == 'true'
          : text;
    } else if (e.key == 'state') {
      props[e.key] = 'unknown';
    }
  }
  props['platform'] = platform;
  return {'name': name, 'props': props};
}

String? _method(Object? mode) => switch (mode?.toString()) {
  'manual' => 'manual',
  'provider' || 'mobile_money' => 'mobile_money',
  _ => null,
};

String currentAnalyticsPlatform() => kIsWeb
    ? 'web'
    : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

class EventsAnalyticsTransport with WidgetsBindingObserver {
  EventsAnalyticsTransport._();

  static final EventsAnalyticsTransport instance = EventsAnalyticsTransport._();

  static const maxQueued = 100;
  static const flushAt = 10;
  static const perRequest = 20;
  static const flushEvery = Duration(seconds: 30);

  AnalyticsSender? _send;
  bool _enabled = false;
  bool _observing = false;
  bool _hooked = false;
  Timer? _timer;
  bool _flushing = false;
  final List<Map<String, dynamic>> _queue = [];

  /// Platform name added to every event (tests).
  @visibleForTesting
  String Function() platform = currentAnalyticsPlatform;

  bool get enabled => _enabled;

  @visibleForTesting
  int get queued => _queue.length;

  /// Turns the transport on or off with the server's `analytics.enabled`.
  /// Off clears anything queued, so a switched-off server gets nothing.
  void configure({required bool enabled, AnalyticsSender? send}) {
    if (!_hooked) {
      // Sign-out empties the queue with everything else events keeps.
      _hooked = true;
      EventsCache.clearHooks.add(reset);
    }
    _send = send ?? _send;
    if (enabled == _enabled && send == null) return;
    _enabled = enabled && _send != null;
    if (_enabled) {
      if (!_observing) {
        try {
          WidgetsBinding.instance.addObserver(this);
          _observing = true;
        } catch (_) {}
      }
      _timer ??= Timer.periodic(flushEvery, (_) => flush());
    } else {
      _stop();
    }
  }

  /// Sign-out or switch-off: forget everything held.
  void reset() {
    _queue.clear();
    _stop();
    _enabled = false;
  }

  void _stop() {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observing = false;
    }
  }

  /// Hands one call over. Never throws and never waits.
  void record(String name, Map<String, Object?> props) {
    if (!_enabled) return;
    try {
      final wire = analyticsWire(name, props, platform: platform());
      if (wire == null) return;
      _queue.add(wire);
      while (_queue.length > maxQueued) {
        _queue.removeAt(0);
      }
      if (_queue.length >= flushAt) unawaited(flush());
    } catch (_) {}
  }

  Future<void> flush() async {
    final send = _send;
    if (!_enabled || send == null || _flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty && _enabled) {
        final batch = _queue.take(perRequest).toList();
        _queue.removeRange(0, batch.length);
        var done = false;
        for (var attempt = 0; attempt < 2 && !done; attempt++) {
          try {
            await send(batch);
            done = true;
          } catch (e) {
            // Offline: dropped, not kept. Any other failure: one retry.
            if (isNetworkError(e) || e is ApiException && e.status == 404) {
              break;
            }
          }
        }
        if (!done && !_enabled) break;
      }
    } finally {
      _flushing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      unawaited(flush());
    }
  }
}
