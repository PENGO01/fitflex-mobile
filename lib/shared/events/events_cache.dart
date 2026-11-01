import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last good answers, for low-bandwidth and offline use (spec §11.8):
/// page 1 of the default list and the last [maxDetails] opened details. Held
/// in memory and in SharedPreferences (the store the app already uses); a
/// failed read or write is ignored. Nothing in `member_gyms_tab` keeps an
/// offline list, so this is the module's own small store.
class EventsCache {
  EventsCache._();

  static const listKey = 'events.cache.list.default';
  static const detailPrefix = 'events.cache.detail.';
  static const detailIndexKey = 'events.cache.detail.index';
  static const maxDetails = 10;

  static Map<String, dynamic>? _list;
  static DateTime? _listAt;
  static final Map<String, (DateTime, Map<String, dynamic>)> _details = {};

  /// Callbacks run by [clearAll] (other in-memory copies, e.g. medal
  /// pictures).
  static final List<void Function()> clearHooks = [];

  /// How long a saved results, medals or wallet copy stays usable (security
  /// review M7). Older copies read as missing.
  static const Duration mineMaxAge = Duration(hours: 24);

  /// Clock for the age rule (tests).
  static DateTime Function() clock = DateTime.now;

  /// Sign-out (security review M7): everything this module saved on the
  /// phone, in memory and in SharedPreferences, so the next person on the
  /// phone sees nothing of this member's results, medals or rewards.
  static Future<void> clearAll() async {
    reset();
    for (final h in List.of(clearHooks)) {
      try {
        h();
      } catch (_) {}
    }
    final p = await _prefs();
    if (p == null) return;
    try {
      for (final k in p.getKeys().toList()) {
        if (k.startsWith('events.cache.') ||
            k.startsWith('events.result.asked.')) {
          await p.remove(k);
        }
      }
    } catch (_) {}
  }

  /// [getMine], but a copy older than [mineMaxAge] is dropped and reads as
  /// missing.
  static Future<(DateTime, Map<String, dynamic>)?> getFreshMine(
    String kind,
  ) async {
    final hit = await getMine(kind);
    if (hit == null) return null;
    if (clock().difference(hit.$1) > mineMaxAge) {
      _mine.remove(kind);
      final p = await _prefs();
      try {
        await p?.remove('$minePrefix$kind');
      } catch (_) {}
      return null;
    }
    return hit;
  }

  /// Forget everything (tests).
  static void reset() {
    _list = null;
    _listAt = null;
    _details.clear();
    _mine.clear();
  }

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<void> putList(Map<String, dynamic> page) async {
    _list = page;
    _listAt = DateTime.now();
    final p = await _prefs();
    try {
      await p?.setString(
        listKey,
        jsonEncode({'at': _listAt!.toIso8601String(), 'page': page}),
      );
    } catch (_) {}
  }

  /// The cached default list and when it was saved, or null.
  static Future<(DateTime, Map<String, dynamic>)?> getList() async {
    if (_list != null) return (_listAt!, _list!);
    final p = await _prefs();
    final raw = p?.getString(listKey);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final at = DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now();
      final page = Map<String, dynamic>.from(m['page'] as Map);
      _list = page;
      _listAt = at;
      return (at, page);
    } catch (_) {
      return null;
    }
  }

  static Future<void> putDetail(String id, Map<String, dynamic> json) async {
    final now = DateTime.now();
    _details[id] = (now, json);
    final p = await _prefs();
    if (p == null) return;
    try {
      final index = (p.getStringList(detailIndexKey) ?? [])..remove(id);
      index.insert(0, id);
      while (index.length > maxDetails) {
        final dropped = index.removeLast();
        await p.remove('$detailPrefix$dropped');
        _details.remove(dropped);
      }
      await p.setStringList(detailIndexKey, index);
      await p.setString(
        '$detailPrefix$id',
        jsonEncode({'at': now.toIso8601String(), 'detail': json}),
      );
    } catch (_) {}
  }

  // ── My registrations / orders (S3 spec §5.8: offline shows the last
  // cached page with a notice) ─────────────────────────────────────────────

  static const minePrefix = 'events.cache.mine.';
  static final Map<String, (DateTime, Map<String, dynamic>)> _mine = {};

  static Future<void> putMine(String kind, Map<String, dynamic> page) async {
    final now = DateTime.now();
    _mine[kind] = (now, page);
    final p = await _prefs();
    try {
      await p?.setString(
        '$minePrefix$kind',
        jsonEncode({'at': now.toIso8601String(), 'page': page}),
      );
    } catch (_) {}
  }

  static Future<(DateTime, Map<String, dynamic>)?> getMine(String kind) async {
    final hit = _mine[kind];
    if (hit != null) return hit;
    final p = await _prefs();
    final raw = p?.getString('$minePrefix$kind');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final at = DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now();
      final page = Map<String, dynamic>.from(m['page'] as Map);
      _mine[kind] = (at, page);
      return (at, page);
    } catch (_) {
      return null;
    }
  }

  static Future<(DateTime, Map<String, dynamic>)?> getDetail(String id) async {
    final hit = _details[id];
    if (hit != null) return hit;
    final p = await _prefs();
    final raw = p?.getString('$detailPrefix$id');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final at = DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now();
      final detail = Map<String, dynamic>.from(m['detail'] as Map);
      _details[id] = (at, detail);
      return (at, detail);
    } catch (_) {
      return null;
    }
  }
}
