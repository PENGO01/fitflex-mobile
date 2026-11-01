// Shared fixtures for the events S6 tests (docs/design/events-s6 §8.3).
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'fixtures.dart';
import 's3_support.dart' show s3Routes;

/// Options with the S6 parts switched on as asked.
EventsOptions optsS6({
  bool enabled = true,
  bool runs = true,
  bool public = true,
  bool rewards = true,
  bool medalArt = true,
  bool registration = true,
}) => EventsOptions.fromJson({
  ...optionsS3,
  'registration': registration,
  'results': {
    'enabled': enabled,
    'runs': runs,
    'public': public,
    'rewards': rewards,
    'medalArt': medalArt,
  },
  'runs': {'toleranceBps': 200, 'maxDaysAfter': 7},
});

Map<String, dynamic> resultRow({
  int elapsedMs = 6728000,
  String finishStatus = 'finished',
  int? categoryRank = 12,
  int finishers = 430,
  bool pb = false,
  String sourceType = 'timing_provider',
  String? sourceLabel,
  String? correctionNote,
  String? reasonCode,
  String? correctedAt,
}) => {
  'id': 'res_1',
  'revision': 1,
  'finishStatus': finishStatus,
  'verificationStatus': 'verified',
  'sourceType': sourceType,
  'sourceLabel': ?sourceLabel,
  'netElapsedMs': elapsedMs,
  'elapsedMs': elapsedMs,
  'overallRank': 40,
  'categoryRank': categoryRank,
  'finishersInCategory': finishers,
  'withinCutoff': true,
  'correctedAt': ?correctedAt,
  'reasonCode': ?reasonCode,
  'correctionNote': ?correctionNote,
  'personalBest': {
    'isPersonalBest': pb,
    'previousBestElapsedMs': null,
    'basis': 'same_distance_and_route_type',
  },
};

Map<String, dynamic> resultPayload({
  String stage = 'official',
  Map<String, dynamic>? result = const {},
  String viewer = 'participant',
  String eventType = 'road',
  Map<String, dynamic>? dispute,
  Map<String, dynamic>? visibility,
  List<Map<String, dynamic>> runLinks = const [],
  List<Map<String, dynamic>> medals = const [],
  List<Map<String, dynamic>> rewards = const [],
  String releaseStage = 'official',
  String? registrationStatus,
}) => {
  'registrationId': 'reg_1',
  'eventId': 'evt_1',
  'eventTitle': 'Dar Half Marathon',
  'eventType': eventType,
  'categoryId': 'cat_21',
  'categoryName': '21K',
  'distanceMeters': 21097,
  'bibNumber': '1042',
  'stage': stage,
  'viewer': viewer,
  'result': result == null ? null : (result.isEmpty ? resultRow() : result),
  'release': {'stage': releaseStage, 'releasedAt': '2027-03-15T10:00:00Z'},
  'dispute':
      dispute ??
      {
        'id': null,
        'status': null,
        'canRaise': true,
        'windowEndsAt': '2027-03-22T10:00:00Z',
      },
  'visibility':
      visibility ??
      {
        'current': 'standard',
        'canChange': true,
        'allowed': ['standard', 'bib_only', 'hidden'],
      },
  'runLinks': runLinks,
  'medals': medals,
  'rewardsEarned': rewards,
  'registrationStatus': ?registrationStatus,
};

Map<String, dynamic> medalJson({
  String id = 'aw_1',
  String status = 'awarded',
  String artSource = 'builtin',
  String? artId,
  String? reasonCode,
  String? revokedAt,
}) => {
  'id': id,
  'eventId': 'evt_1',
  'eventTitle': 'Dar Half Marathon',
  'organizerName': 'Dar Runners',
  'categoryName': '21K',
  'templateId': 'tpl_1',
  'tier': 'finisher',
  'name': {'en': 'Finisher', 'sw': 'Mshindi'},
  'description': {'en': 'Finished the race', 'sw': 'Alimaliza mbio'},
  'art': {
    'source': artSource,
    'artId': artId,
    'revision': artId == null ? null : 1,
    'artKey': 'finisher_green',
    'altText': null,
  },
  'status': status,
  'awardedAt': '2027-03-15T10:00:00Z',
  'revokedAt': revokedAt,
  'reasonCode': reasonCode,
  'resultSummary': {'rank': 12, 'elapsedMs': 6728000},
};

/// Stand-in pages for the routes the S6 screens go to.
final s6Routes = <RouteBase>[
  ...s3Routes,
  GoRoute(
    path: AppRoutes.memberEventResult,
    builder: (_, s) => Scaffold(
      body: Text('ROUTE-RESULT-${s.pathParameters['registrationId']}'),
    ),
  ),
  GoRoute(
    path: AppRoutes.memberEventRuns,
    builder: (_, s) => Scaffold(
      body: Text('ROUTE-RUNS-${s.pathParameters['registrationId']}'),
    ),
  ),
  GoRoute(
    path: AppRoutes.memberEventMedals,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-MEDALS')),
  ),
  GoRoute(
    path: AppRoutes.memberEventRewards,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-REWARDS')),
  ),
  GoRoute(
    path: AppRoutes.memberEventMyResults,
    builder: (_, _) => const Scaffold(body: Text('ROUTE-MYRESULTS')),
  ),
  GoRoute(
    path: AppRoutes.memberRecordRun,
    builder: (_, s) => Scaffold(
      body: Text('ROUTE-RECORD-${s.uri.queryParameters['registration']}'),
    ),
  ),
];
