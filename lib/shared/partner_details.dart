// Partner date of birth (plan slice 3, fitflex-functions#253): the date of
// birth, and for gym owners the gender, a Trainer or gym owner gives for
// shop suggestions. Kept on the Person (one per human, across personas) via
// GET/PUT /me/personal-details. Never KYC data. While the server flag
// PARTNER_DOB_REQUIRED is off the GET answers 404 feature_disabled and the
// app shows nothing new.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_error_message.dart';
import 'date_of_birth.dart';
import 'i18n.dart';

/// Which partner role a date-of-birth screen or explanation is for: the
/// wording differs (a Trainer's gender comes from the trainer profile).
enum PartnerRole { trainer, owner }

/// Trainers and gym owners must be this old (owner decision 2026-10-22).
const int partnerMinAge = 18;

/// The gender choices a gym owner has; [partnerGenderPreferNot] is sent as
/// null ("prefer not to say").
const partnerGenders = ['male', 'female', 'other'];
const partnerGenderPreferNot = 'none';

/// GET /me/personal-details.
class PersonalDetails {
  const PersonalDetails({
    this.dateOfBirth,
    this.gender,
    this.source,
    this.ask = false,
    this.required = false,
    this.genderFrom,
  });

  factory PersonalDetails.fromJson(Map<String, dynamic> json) {
    String? text(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return PersonalDetails(
      dateOfBirth: text(json['dateOfBirth']),
      gender: text(json['gender']),
      source: text(json['source']),
      ask: json['ask'] == true,
      required: json['required'] == true,
      genderFrom: text(json['genderFrom']),
    );
  }

  /// "YYYY-MM-DD" or null.
  final String? dateOfBirth;

  /// male | female | other | null.
  final String? gender;

  /// 'person' (given here), 'member' (from the member profile) or null.
  final String? source;

  /// The person holds a Trainer or gym-owner role and has no date of birth:
  /// ask for it.
  final bool ask;

  /// The person holds a Trainer or gym-owner role.
  final bool required;

  /// 'trainer_profile' (the trainer profile's gender, read-only here),
  /// 'person' or null.
  final String? genderFrom;

  bool get genderFromTrainerProfile => genderFrom == 'trainer_profile';
}

/// GET /me/personal-details, or null when the feature is off
/// (404 feature_disabled) or the call failed. Null means: show nothing new
/// and never block anyone (the old behaviour).
Future<PersonalDetails?> loadPersonalDetails(
  ApiClient api, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final body = await api.personalDetails().timeout(timeout);
    return PersonalDetails.fromJson(body);
  } catch (_) {
    return null;
  }
}

/// One GET /me/personal-details per signed-in account per session, shared
/// by the home card and the settings tile, and replaced by what a save
/// answers (security review L1). A feature-disabled answer is kept too (no
/// new UI for the session); any other failure is not kept, so the next
/// screen asks again. Registration pages read fresh ([loadPersonalDetails]).
class PartnerDetailsSession {
  PartnerDetailsSession._();

  static String? _account;
  static Future<PersonalDetails?>? _pending;

  /// The details for the account last loaded, or null (not loaded, off or
  /// failed). Widgets listen so a save in one place updates the other.
  static final ValueNotifier<PersonalDetails?> current = ValueNotifier(null);

  /// The details for [account], from the session copy when there is one.
  static Future<PersonalDetails?> load(ApiClient api, String account) {
    final pending = _pending;
    if (pending != null && _account == account) return pending;
    _account = account;
    current.value = null;
    late final Future<PersonalDetails?> future;
    future = _fetch(api).then((result) {
      if (!identical(_pending, future)) return result.$1;
      if (result.$2) {
        current.value = result.$1;
      } else {
        _pending = null; // not kept: try again next time
      }
      return result.$1;
    });
    _pending = future;
    return future;
  }

  /// (details, keep): keep is false for a failure worth retrying.
  static Future<(PersonalDetails?, bool)> _fetch(ApiClient api) async {
    try {
      final body = await api.personalDetails().timeout(
        const Duration(seconds: 8),
      );
      return (PersonalDetails.fromJson(body), true);
    } on ApiException catch (e) {
      return (null, e.code == 'feature_disabled');
    } catch (_) {
      return (null, false);
    }
  }

  /// What a save answered, for [account].
  static void saved(String account, PersonalDetails details) {
    _account = account;
    _pending = Future.value(details);
    current.value = details;
  }

  /// Sign-out (and tests): forget the session copy.
  static void clear() {
    _account = null;
    _pending = null;
    current.value = null;
  }
}

/// Whole years from [dateOfBirth] to today in East Africa, as the server
/// counts them (src/shared/date-of-birth.mjs ageOnDay).
int ageOn(DateTime dateOfBirth, {DateTime? now}) {
  final today = eastAfricaToday(now: now);
  final before =
      today.month < dateOfBirth.month ||
      (today.month == dateOfBirth.month && today.day < dateOfBirth.day);
  return today.year - dateOfBirth.year - (before ? 1 : 0);
}

/// True when [dateOfBirth] is a real date and the person is under 18 today
/// (on their 18th birthday they are not).
bool isUnderPartnerAge(String? dateOfBirth, {DateTime? now}) {
  final date = parseDateOfBirth(dateOfBirth?.trim() ?? '');
  if (date == null) return false;
  return ageOn(date, now: now) < partnerMinAge;
}

/// The i18n key for what is wrong with a partner's date of birth, else
/// null. [required]: empty is not allowed.
String? partnerDobProblemKey(
  String? value, {
  bool required = true,
  DateTime? now,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return required ? 'onboarding.required' : null;
  final problem = dateOfBirthProblemKey(text, now: now);
  if (problem != null) return problem;
  if (isUnderPartnerAge(text, now: now)) return 'error.reason.partnerUnder18';
  return null;
}

bool _isCode(Object error, String code) =>
    error is ApiException && error.code?.trim().toLowerCase() == code;

/// 400 partner_under_18 (PUT /me/personal-details, the register routes,
/// POST /me/personas, POST /me/profile).
bool isPartnerUnder18Error(Object error) => _isCode(error, 'partner_under_18');

/// 400 invalid_field gender.
bool isGenderFieldError(Object error) =>
    _isCode(error, 'invalid_field') &&
    (error as ApiException).body is Map &&
    (error.body as Map)['field'] == 'gender';

/// The line for a refused personal-details save (or a register/role/profile
/// call refused for the partner age rule), without the generic "Request
/// declined" prefix. Anything else goes through [errorMessage].
String partnerDetailsErrorMessage(FFLocale locale, Object error) {
  if (isPartnerUnder18Error(error)) {
    return locale.t('error.reason.partnerUnder18');
  }
  if (isDateOfBirthError(error)) return locale.t('member.dobInvalid');
  if (isGenderFieldError(error)) return locale.t('error.reason.invalidGender');
  if (_isCode(error, 'personal_details_unavailable')) {
    return locale.t('error.reason.personalDetailsUnavailable');
  }
  if (_isCode(error, 'rate_limited')) {
    final body = (error as ApiException).body;
    final raw = body is Map ? body['retryAfterSeconds'] : null;
    final n = raw is num ? raw.ceil() : int.tryParse(raw?.toString() ?? '');
    if (n != null && n > 0) {
      return locale
          .t('partnerDob.errRateLimited')
          .replaceFirst('{seconds}', '$n');
    }
  }
  return errorMessage(locale, error);
}

/// The home-screen prompt for existing Trainers and gym owners with no date
/// of birth: never blocking, dismissible, asked again 30 days after "Not
/// now", and not again after 3 dismissals. Kept on this device per account.
class PartnerDobPromptStore {
  PartnerDobPromptStore._();

  static const maxDismissals = 3;
  static const askAgainAfter = Duration(days: 30);

  static String countKey(String account) => 'ff.partnerDob.dismissals.$account';
  static String atKey(String account) => 'ff.partnerDob.dismissedAt.$account';

  /// Whether the prompt may show for [account] now.
  static Future<bool> mayShow(String account, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(countKey(account)) ?? 0;
      if (count >= maxDismissals) return false;
      final at = prefs.getInt(atKey(account));
      if (at == null) return true;
      final last = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
      return !(now ?? DateTime.now()).toUtc().isBefore(last.add(askAgainAfter));
    } catch (_) {
      return true;
    }
  }

  /// Sign-out (security review L2): remove every prompt count kept on this
  /// device, so the next person to sign in here starts clean.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('ff.partnerDob.')) await prefs.remove(key);
      }
    } catch (_) {
      // Nothing kept, or storage unavailable.
    }
  }

  /// "Not now": one more dismissal, and wait 30 days.
  static Future<void> dismiss(String account, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(countKey(account)) ?? 0;
      await prefs.setInt(countKey(account), count + 1);
      await prefs.setInt(
        atKey(account),
        (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Not kept; the prompt may show again next time.
    }
  }
}
