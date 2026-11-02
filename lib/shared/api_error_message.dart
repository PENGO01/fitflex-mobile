import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'formatters.dart';
import 'i18n.dart';

/// Any caught error → user-facing copy (UAT #48). Prefer this over
/// `e.toString()`, which shows raw text like "ApiException(400, {...})".
///
/// [vendorStaff]: the caller is vendor staff, so `account_suspended` means
/// their staff access was turned off (vendor tools S2).
String errorMessage(FFLocale locale, Object error, {bool vendorStaff = false}) {
  if (error is ApiException) {
    return apiErrorMessage(locale, error, vendorStaff: vendorStaff);
  }
  if (isNetworkError(error)) return locale.t('error.network');
  return locale.t('error.requestFailed');
}

/// Events (S4): like [errorMessage], but `payment_in_progress` and
/// `unsupported_currency` say what they mean for event tickets instead of
/// the trainer-booking and mobile-money wording the shared map keeps.
String eventsErrorMessage(FFLocale locale, Object error) {
  if (error is ApiException) {
    final key = switch (error.code) {
      'payment_in_progress' => 'error.reason.payment_in_progress',
      'unsupported_currency' => 'error.reason.unsupported_currency',
      _ => null,
    };
    if (key != null) {
      return locale
          .t('error.requestDeclined')
          .replaceFirst('{reason}', locale.t(key));
    }
  }
  return errorMessage(locale, error);
}

/// A refused trainer-booking cancel (member or trainer side). While a
/// mobile-money prompt is out for the booking the server answers
/// 409 payment_in_progress (fitflex-functions#240): say so plainly.
String bookingCancelErrorMessage(FFLocale locale, Object error) {
  if (error is ApiException &&
      _firstReason(error.body)?.trim().toLowerCase() == 'payment_in_progress') {
    return locale.t('error.reason.bookingPaymentInProgress');
  }
  return errorMessage(locale, error);
}

/// The request never reached the server (offline, DNS, timeout), as
/// opposed to the server answering with an error.
bool isNetworkError(Object error) {
  if (error is ApiException) return false;
  if (error is TimeoutException || error is http.ClientException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup');
}

/// Converts API failures into user-facing copy. Backend validation/decline
/// reasons win over the HTTP status so a 400 never leaks into the UI alone.
String apiErrorMessage(
  FFLocale locale,
  ApiException exception, {
  bool vendorStaff = false,
}) {
  if (isVendorStaffDisabled(exception, vendorStaff: vendorStaff)) {
    return locale.t('error.reason.vendorStaffInactive');
  }
  // Events S3: `hold_limit_reached` carries a second field (`limit`, e.g.
  // 'unpaid_order_exists'); its `error` code is what names the refusal,
  // whatever other reason-like key sits beside it.
  final body = exception.body;
  // invalid_media_src carries its own `reason` (too_large, …): the `error`
  // code names the refusal, the reason only picks the wording.
  final reason =
      body is Map &&
          (body['error'] == 'hold_limit_reached' ||
              body['error'] == 'invalid_media_src' ||
              // Carries `message`/`messageSw`; the code still names it.
              body['error'] == 'organizer_owner')
      ? body['error'] as String
      : _firstReason(body);
  if (reason != null && reason.isNotEmpty) {
    final translated =
        _timedReason(locale, reason, exception.body) ??
        _detailedReason(locale, reason, exception.body) ??
        _knownReason(locale, reason) ??
        _humanize(reason);
    return locale
        .t('error.requestDeclined')
        .replaceFirst('{reason}', translated);
  }

  final key = switch (exception.status) {
    401 => 'error.unauthorized',
    403 => 'error.forbidden',
    404 => 'error.notFound',
    409 => 'error.conflict',
    _ => 'error.requestFailed',
  };
  return locale.t(key);
}

/// The translated reason for one server code (no "request declined"
/// wrapper), for banners that list several problems (the quote's
/// `problems[]`, §3.4). [extra] holds numbers such as `min` / `max`.
String errorReasonText(
  FFLocale locale,
  String code, [
  Map<String, dynamic>? extra,
]) {
  final body = <String, dynamic>{...?extra, 'error': code};
  return _detailedReason(locale, code, body) ??
      _knownReason(locale, code) ??
      _humanize(code);
}

/// Vendor staff whose access the business owner turned off (vendor tools
/// S2, fitflex-functions#200): `vendor_staff_inactive` from vendor routes and
/// PIN sign-in, or `account_suspended` (the token check runs first) when the
/// caller is vendor staff. For anyone else `account_suspended` keeps its
/// own message.
bool isVendorStaffDisabled(Object error, {bool vendorStaff = false}) {
  if (error is! ApiException) return false;
  final reason = _firstReason(error.body)?.trim().toLowerCase();
  if (reason == 'vendor_staff_inactive') return true;
  return vendorStaff && reason == 'account_suspended';
}

String? _firstReason(dynamic value) {
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is List) {
    for (final item in value) {
      final reason = _firstReason(item);
      if (reason != null) return reason;
    }
    return null;
  }
  if (value is Map) {
    for (final key in const [
      'reason',
      'failure', // check-in declines: { ok:false, failure:'visits_exhausted' }
      'message',
      'error_description',
      'error',
      'detail',
      'details',
      'errors',
    ]) {
      if (value.containsKey(key)) {
        final reason = _firstReason(value[key]);
        if (reason != null) return reason;
      }
    }
  }
  return null;
}

/// Refusals that carry the time they are about (trainer session outcomes,
/// fitflex-functions#231): the start of a session that hasn't begun, or
/// when the window to record a missed session closed. Null when the body has
/// no readable time, so the plain wording is used.
String? _timedReason(FFLocale locale, String reason, dynamic body) {
  if (body is! Map) return null;
  final (String field, String key) = switch (reason.trim().toLowerCase()) {
    'session_not_started' => ('startsAt', 'error.reason.sessionNotStartedAt'),
    'no_show_window_passed' => (
      'closedAt',
      'error.reason.noShowWindowPassedAt',
    ),
    _ => ('', ''),
  };
  if (field.isEmpty || localDateTime(body[field]) == null) return null;
  final time = formatDayTime(body[field], locale: locale.locale.languageCode);
  return locale.t(key).replaceFirst('{time}', time);
}

/// Refusals whose details change the wording (mobile money for trainer
/// products, fitflex-functions#240): which account pays for a product, and
/// which pass tier is off sale. Null falls back to the plain wording.
String? _detailedReason(FFLocale locale, String reason, dynamic body) {
  if (body is! Map) return null;
  switch (reason.trim().toLowerCase()) {
    // Events S3 (spec §3.17): refusals that carry numbers, and the order /
    // registration state machines' `invalid_transition { kind }`.
    case 'quantity_out_of_range':
      if (body['min'] is! num || body['max'] is! num) return null;
      return locale
          .t('error.reason.quantityOutOfRange')
          .replaceFirst('{min}', '${body['min']}')
          .replaceFirst('{max}', '${body['max']}');
    // Events S6: the distance the run has to reach (metres in the body).
    case 'distance_too_short':
      if (body['requiredMeters'] is! num) return null;
      return locale
          .t('events.run.error.distance_too_short')
          .replaceFirst(
            '{distance}',
            '${((body['requiredMeters'] as num) / 1000).toStringAsFixed(2)} km',
          );
    // Account deletion for an organizer owner (DELETE /me, 409): the server
    // sends the sentence in both languages.
    case 'organizer_owner':
      final lang = locale.locale.languageCode;
      final text = (lang == 'sw' ? body['messageSw'] : body['message'])
          ?.toString()
          .trim();
      return text == null || text.isEmpty
          ? locale.t('events.error.organizer_owner')
          : text;
    case 'too_many_participants':
      if (body['max'] is! num) return null;
      return locale
          .t('error.reason.tooManyParticipants')
          .replaceFirst('{max}', '${body['max']}');
    case 'invalid_transition':
      final kind = body['kind']?.toString();
      if (kind == 'order' || kind == 'registration') {
        return locale.t('error.reason.invalidTransition.events');
      }
      return null;
    // Which field the server refused (fitflex-functions#253, #239).
    case 'invalid_field':
      return switch (body['field']?.toString()) {
        'dateOfBirth' => locale.t('member.dobInvalid'),
        'gender' => locale.t('error.reason.invalidGender'),
        _ => null,
      };
    // A refused photo (fitflex-functions#273): { field, index?, reason }.
    case 'invalid_media_src':
      return locale.t(switch (body['reason']?.toString()) {
        'too_large' || 'image_too_large' => 'error.reason.mediaSrcTooLarge',
        _ => 'error.reason.invalidMediaSrc',
      });
    // Over a photo count cap (fitflex-functions#273): { field, max }.
    case 'too_many_images':
      final max = body['max'];
      final n = max is num ? max.toInt() : int.tryParse(max?.toString() ?? '');
      if (n == null || n <= 0) return null;
      return locale.t('photos.max').replaceAll('{n}', '$n');
    // 429 with the wait the server gave.
    case 'rate_limited':
      final seconds = body['retryAfterSeconds'];
      final n = seconds is num
          ? seconds.ceil()
          : int.tryParse(seconds?.toString() ?? '');
      if (n == null || n <= 0) return null;
      return locale
          .t('error.reason.rateLimitedSeconds')
          .replaceFirst('{seconds}', '$n');
    case 'not_payable_by_role':
      final product = body['product']?.toString();
      if (product == null) return null;
      return locale.t(
        product == 'TRAINER_GYM_PASS'
            ? 'error.reason.notPayableByRoleTrainer'
            : 'error.reason.notPayableByRoleMember',
      );
    case 'tier_not_available':
      final tier = body['tier']?.toString().trim() ?? '';
      if (tier.isEmpty) return null;
      // Tier names stay English (owner, Swahili review 2026-10-04).
      final name = '${tier[0].toUpperCase()}${tier.substring(1)}';
      return locale
          .t('error.reason.tierNotAvailableNamed')
          .replaceFirst('{tier}', name);
  }
  return null;
}

String? _knownReason(FFLocale locale, String reason) {
  const keys = {
    'membership_expired': 'error.reason.membershipExpired',
    'gym_tier_not_covered': 'error.reason.gymTierNotCovered',
    'visit_cap_reached': 'error.reason.visitCapReached',
    'slot_unavailable': 'error.reason.slotUnavailable',
    'payment_declined': 'error.reason.paymentDeclined',
    // Check-in (BL-012) — codes the backend actually returns.
    'subscription_inactive': 'error.reason.membershipExpired',
    'tier_not_covered': 'error.reason.gymTierNotCovered',
    'visits_exhausted': 'error.reason.visitCapReached',
    'gym_closed': 'error.reason.gymClosed',
    // Account deletion (DELETE /me): support has to step in first.
    'gym_owner_has_checkin_activity': 'error.reason.gymOwnerHasCheckins',
    'trainer_has_bookings': 'error.reason.trainerHasBookings',
    'open_paid_order': 'error.reason.openPaidOrder',
    'whatsapp_template_required': 'error.reason.whatsappTemplateRequired',
    'basic_daily_limit': 'error.reason.basicDailyLimit',
    'invalid_or_expired_qr': 'error.reason.qrExpired',
    'invalid_gym_qr': 'error.reason.invalidGymQr',
    'not_your_gym': 'error.reason.notYourGym',
    'gym_required': 'error.reason.gymRequired',
    'wrong_gym': 'error.reason.wrongGym',
    'gym_not_verified': 'error.reason.gymNotVerified',
    'trainer_not_verified': 'error.reason.trainerNotVerified',
    'operator_not_assigned_to_gym': 'error.reason.operatorNotAssigned',
    'member_not_found': 'error.reason.memberNotFound',
    'gym_not_found': 'error.reason.gymNotFound',
    'tier_not_configured': 'error.reason.tierNotConfigured',
    // Trainer booking.
    'slot_already_booked': 'error.reason.slotUnavailable',
    'slot_not_available': 'error.reason.slotUnavailable',
    'slot_in_past': 'error.reason.slotInPast',
    // Cancellations and refunds.
    'cancellation_window_passed': 'error.reason.cancelWindowPassed',
    'session_already_started': 'error.reason.sessionStarted',
    'booking_not_cancellable': 'error.reason.bookingNotCancellable',
    'order_already_dispatched': 'error.reason.orderDispatched',
    'order_already_delivered': 'error.reason.orderDispatched',
    'order_cancelled': 'error.reason.orderCancelled',
    'refund_already_requested': 'error.reason.refundAlreadyRequested',
    // Trainer session outcomes (fitflex-functions#231).
    'session_not_started': 'error.reason.sessionNotStarted',
    'booking_not_confirmable': 'error.reason.bookingNotConfirmable',
    'booking_not_confirmed': 'error.reason.bookingNotConfirmed',
    'no_show_window_passed': 'error.reason.noShowWindowPassed',
    'booking_cancelled': 'error.reason.bookingCancelled',
    'booking_changed': 'error.reason.bookingChanged',
    'booking_on_trainer_statement': 'error.reason.bookingOnTrainerStatement',
    'invalid_booking_time': 'error.reason.invalidBookingTime',
    'cannot_book_own_sessions': 'error.reason.cannotBookOwnSessions',
    // Pass and gym-plan purchases.
    'payment_already_pending': 'error.reason.paymentAlreadyPending',
    'plan_not_offered': 'error.reason.planNotOffered',
    'gym_not_available': 'error.reason.gymNotAvailable',
    'tier_not_available': 'error.reason.tierNotAvailable',
    // Manual Lipa Namba payment (fitflex-functions#188).
    'payment_reference_required': 'error.reason.paymentReferenceRequired',
    'payment_reference_invalid': 'error.reason.paymentReferenceInvalid',
    'payment_reference_duplicate': 'error.reason.paymentReferenceDuplicate',
    'manual_payment_submitted': 'error.reason.manualPaymentSubmitted',
    'payer_phone_required': 'error.reason.payerPhoneRequired',
    'payer_phone_invalid': 'error.reason.payerPhoneInvalid',
    'invalid_tier': 'error.reason.tierNotAvailable',
    'not_an_upgrade': 'error.reason.notAnUpgrade',
    'invalid_phone': 'error.reason.invalidPhone',
    'too_many_attempts': 'error.reason.tooManyAttempts',
    'payment_in_progress': 'error.reason.paymentInProgress',
    'provider_unavailable': 'error.reason.providerUnavailable',
    'provider_rejected': 'error.reason.providerRejected',
    'payment_not_pending': 'error.reason.paymentNotPending',
    'not_payable_this_way': 'error.reason.notPayableThisWay',
    'not_payable_by_role': 'error.reason.notPayableByRole',
    'group_slot_rebooked': 'error.reason.groupSlotRebooked',
    'unsupported_currency': 'error.reason.unsupportedCurrency',
    'sponsored_pass': 'error.reason.sponsoredPass',
    // Accounts.
    'email_already_used': 'error.reason.emailAlreadyUsed',
    'invalid_credentials': 'error.reason.invalidCredentials',
    'account_suspended': 'error.reason.accountSuspended',
    'acl_forbidden': 'error.reason.noPermission',
    // Photos (fitflex-functions#273).
    'invalid_media_src': 'error.reason.invalidMediaSrc',
    'upload_forbidden': 'error.reason.uploadForbidden',
    'too_many_images': 'error.reason.tooManyImages',
    'active_subscription_required': 'error.reason.activeSubscriptionRequired',
    // Communications.
    'confirm_large_send': 'error.reason.confirmLargeSend',
    'nobody_reachable': 'error.reason.nobodyReachable',
    'empty_audience': 'error.reason.emptyAudience',
    'invalid_state': 'error.reason.campaignChanged',
    'not_editable': 'error.reason.campaignChanged',
    'channel_unavailable': 'error.reason.channelUnavailable',
    'schedule_too_soon': 'error.reason.scheduleTooSoon',
    'invalid_content': 'error.reason.invalidContent',
    'invalid_audience': 'error.reason.invalidAudience',
    // Vendor products and verification.
    'invalid_category': 'error.reason.invalidCategory',
    'invalid_product_category': 'error.reason.invalidCategory',
    'invalid_position': 'error.reason.invalidPosition',
    // Reviews.
    'no_completed_booking': 'error.reason.noCompletedBooking',
    'no_checkin_or_direct_subscription': 'error.reason.noGymVisit',
    'rating_must_be_integer_1_to_5': 'error.reason.invalidRating',
    'text_too_short': 'error.reason.reviewTextTooShort',
    'text_too_long': 'error.reason.reviewTextTooLong',
    // Events (Marathon & Running Events S2, spec §14.6).
    'event_not_found': 'error.reason.eventNotFound',
    'feature_disabled': 'error.reason.featureDisabled',
    'rate_limited': 'error.reason.rateLimited',
    'not_your_organizer': 'error.reason.notYourOrganizer',
    'organizer_not_active': 'error.reason.organizerNotActive',
    'organizer_suspended': 'error.reason.organizerSuspended',
    'forbidden_role': 'error.reason.noPermission',
    'invalid_transition': 'error.reason.invalidTransition',
    'version_conflict': 'error.reason.versionConflict',
    'event_invalid': 'error.reason.eventInvalid',
    'change_note_required': 'error.reason.changeNoteRequired',
    'has_registrations': 'error.reason.hasRegistrations',
    'organizer_exists': 'error.reason.organizerExists',
    'persona_not_allowed': 'error.reason.personaNotAllowed',
    'already_staff': 'error.reason.alreadyStaff',
    'invalid_contact': 'error.reason.invalidContact',
    'cannot_invite_self': 'error.reason.cannotInviteSelf',
    'cannot_remove_owner': 'error.reason.cannotRemoveOwner',
    'kyc_incomplete': 'error.reason.kycIncomplete',
    // Events S6: runs, results, rewards (spec §8, §10).
    'run_outside_window': 'events.run.error.run_outside_window',
    'distance_too_short': 'events.run.error.distance_too_short',
    'activity_not_recorded_in_app':
        'events.run.error.activity_not_recorded_in_app',
    'activity_already_linked': 'events.run.error.activity_already_linked',
    'run_already_linked': 'events.run.error.run_already_linked',
    'event_not_open_for_results': 'events.run.error.event_not_open_for_results',
    'dispute_open': 'events.result.error.dispute_open',
    'dispute_window_closed': 'events.result.dispute.closedWindow',
    'result_not_found': 'events.result.error.result_not_found',
    'visibility_not_allowed': 'events.result.error.visibility_not_allowed',
    'evidence_limit': 'events.error.evidence_limit',
    'link_locked': 'events.error.link_locked',
    'linking_closed': 'events.error.linking_closed',
    'registration_not_confirmed': 'events.error.registration_not_confirmed',
    'result_exists': 'events.error.result_exists',
    'no_result': 'events.error.no_result',
    'rewards_unavailable': 'events.error.rewards_unavailable',
    'dispute_closed': 'events.error.dispute_closed',
    'dispute_not_found': 'events.error.dispute_not_found',
    'request_in_progress': 'events.error.request_in_progress',
    'redemption_expired': 'events.error.redemption_expired',
    'activity_not_found': 'events.error.activity_not_found',
    'link_not_found': 'events.error.link_not_found',
    'invalid_route': 'run.fail.weakGps',
    'reward_unavailable': 'events.rewards.error.reward_unavailable',
    'not_enough_units': 'events.rewards.error.not_enough_units',
    // Events S3: registration, orders, claims, teams (spec §3.17).
    'capacity_unavailable': 'error.reason.capacityUnavailable',
    'event_not_open': 'error.reason.eventNotOpen',
    'registration_closed': 'error.reason.registrationClosed',
    'sale_closed': 'error.reason.saleClosed',
    'sale_not_open': 'error.reason.saleNotOpen',
    'ticket_type_inactive': 'error.reason.ticketUnavailable',
    'ticket_type_not_found': 'error.reason.ticketUnavailable',
    'category_inactive': 'error.reason.ticketUnavailable',
    'quantity_out_of_range': 'error.reason.quantityOutOfRange',
    'too_many_participants': 'error.reason.tooManyParticipants',
    'terms_not_accepted': 'error.reason.termsNotAccepted',
    'consent_version_stale': 'error.reason.consentVersionStale',
    'participant_invalid': 'error.reason.participantInvalid',
    'invalid_participant': 'error.reason.participantInvalid',
    'participants_mismatch': 'error.reason.participantInvalid',
    'multiple_self_participants': 'error.reason.multipleSelf',
    'invalid_text': 'error.reason.invalidText',
    'field_too_long': 'error.reason.fieldTooLong',
    'team_name_invalid': 'error.reason.teamNameInvalid',
    'team_type_invalid': 'error.reason.teamTypeInvalid',
    'raw_text_too_long': 'error.reason.rawTextTooLong',
    'capacity_short': 'error.reason.capacityUnavailable',
    'price_changed': 'error.reason.priceChanged',
    'order_not_found': 'error.reason.orderNotFound',
    'registration_not_found': 'error.reason.registrationNotFound',
    'invalid_reason': 'error.reason.invalidReason',
    'remove_whole_line': 'error.reason.removeWholeLine',
    'team_not_found': 'error.reason.teamNotFound',
    'team_full': 'error.reason.teamFull',
    'team_disbanded': 'error.reason.teamDisbanded',
    'team_name_taken': 'error.reason.teamNameTaken',
    'claim_token_invalid': 'error.reason.claimTokenInvalid',
    'claim_token_expired': 'error.reason.claimTokenExpired',
    'claim_not_verified': 'error.reason.claimNotVerified',
    'already_claimed': 'error.reason.alreadyClaimed',
    'claim_own_contact': 'error.reason.claimOwnContact',
    'registration_closed_state': 'error.reason.registrationClosedState',
    'idempotency_key_reused': 'error.reason.idempotencyKeyReused',
    'idempotency_key_required': 'error.reason.idempotencyKeyReused',
    'organization_not_allowed': 'error.reason.organizationNotAllowed',
    'hold_limit_reached': 'error.reason.holdLimitReached',
    // Always sent by the app; only a stale client would see it.
    'expected_total_required': 'error.reason.priceChanged',
    // Events S4: payments, tickets, cancel and refund (spec §3.17).
    'order_not_payable': 'error.reason.order_not_payable',
    'hold_expired': 'error.reason.hold_expired',
    'payment_submitted': 'error.reason.payment_submitted',
    'tickets_unavailable': 'error.reason.tickets_unavailable',
    'payment_mode_mismatch': 'error.reason.payment_mode_mismatch',
    'ticket_revoked': 'error.reason.ticket_revoked',
    'ticket_not_issued': 'error.reason.ticket_not_issued',
    'refund_changed': 'error.reason.refund_changed',
    'refund_in_progress': 'error.reason.refund_in_progress',
    'cancellation_window_closed': 'error.reason.cancellation_window_closed',
    'purchaser_only': 'error.reason.purchaser_only',
    'resend_limit_reached': 'error.reason.resend_limit_reached',
    'event_cancelled': 'error.reason.event_cancelled',
    'kit_collected': 'error.reason.kit_collected',
    'order_not_confirmed': 'error.reason.order_not_confirmed',
    'rotate_required': 'error.reason.rotate_required',
    'event_unavailable': 'error.reason.event_unavailable',
    // Partner date of birth (fitflex-functions#253).
    'partner_under_18': 'error.reason.partnerUnder18',
    'personal_details_unavailable': 'error.reason.personalDetailsUnavailable',
  };
  final key = keys[reason.trim().toLowerCase()];
  return key == null ? null : locale.t(key);
}

String _humanize(String value) {
  final clean = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return value;
  return '${clean[0].toUpperCase()}${clean.substring(1)}';
}
