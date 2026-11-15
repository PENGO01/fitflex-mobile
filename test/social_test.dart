import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_community_page.dart';
import 'package:fitflexmobile/screens/member/member_group_page.dart';
import 'package:fitflexmobile/screens/member/member_person_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_shared_activity_page.dart';
import 'package:fitflexmobile/screens/member/widgets/share_picker.dart';
import 'package:fitflexmobile/shared/activity/manual_activity_log.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item({
  String id = 'a1',
  String owner = 'ben',
  String rel = 'friends',
  int kudos = 0,
  bool mine = false,
}) => {
  'activity': {
    'id': id,
    'userId': owner,
    'type': 'running',
    'startedAt': '2026-09-25T05:00:00.000Z',
    'durationMinutes': 28,
    'distanceKm': 5.2,
    'movingSeconds': 1680,
    'elevationGainM': 12,
    'splits': [330, 320, 340, 330, 340],
    'title': 'Morning run',
  },
  'owner': {
    'id': owner,
    'displayName': owner == 'ben' ? 'Ben Mushi' : 'Ana',
    'relationship': mine ? 'you' : rel,
  },
  'kudos': kudos,
  'youKudoed': false,
  'comments': 1,
};

class _Api extends ApiClient {
  final calls = <String>[];
  List<Map<String, dynamic>> feedItems = [_item()];
  List<Map<String, dynamic>> groups = [];
  Map<String, dynamic> conn = {
    'friends': [
      {'id': 'ben', 'displayName': 'Ben Mushi', 'relationship': 'friends'},
    ],
    'following': [],
    'followers': [
      {'id': 'cy', 'displayName': 'Cy Juma', 'relationship': 'follows_you'},
    ],
  };

  @override
  Future<Map<String, dynamic>> feed({String? before}) async => {
    'items': feedItems,
    'next': null,
  };
  @override
  Future<Map<String, dynamic>> kudos(String id, bool on) async {
    calls.add('kudos:$id:$on');
    return {'kudos': on ? 1 : 0, 'youKudoed': on, 'comments': 1};
  }

  bool publicProfile = false;
  Map<String, dynamic>? profileResponse;

  @override
  Future<Map<String, dynamic>> explore({String? before}) async => {
    'items': [_item(id: 'pub1', owner: 'ben', rel: 'none')],
    'next': null,
  };

  @override
  Future<Map<String, dynamic>> personProfile(
    String userId, {
    String? before,
  }) async =>
      profileResponse ??
      {
        'person': {
          'id': userId,
          'displayName': 'Ben Mushi',
          'relationship': 'none',
          'publicProfile': true,
          'followers': 1200,
          'following': 80,
        },
        'items': [_item(id: 'pub1', owner: userId, rel: 'none')],
        'next': null,
      };

  @override
  Future<Map<String, dynamic>> postEngagement(String activityId) async => {
    'views': 42,
    'kudos': [
      {'id': 'fan', 'displayName': 'Juma Fan', 'relationship': 'follows_you'},
    ],
    'commenters': [
      {'id': 'ana', 'displayName': 'Ana', 'relationship': 'friends'},
    ],
  };

  @override
  Future<Map<String, dynamic>> connections() async => conn;

  @override
  Future<Map<String, dynamic>> friendInvitations() async => {
    'incoming': [],
    'outgoing': outgoing,
  };

  List<Map<String, dynamic>> outgoing = [];

  Map<String, dynamic> inviteDelivery = {};
  Map<String, dynamic> lookupDelivery = {'sms': false, 'whatsapp': false};

  @override
  Future<Map<String, dynamic>> friendLookup({
    String? email,
    String? phone,
  }) async {
    calls.add('lookup:${phone ?? email}');
    return {
      'result': {
        'kind': 'unregistered',
        'contactType': phone != null ? 'phone' : 'email',
        'delivery': lookupDelivery,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> inviteFriend({
    String? userId,
    String? email,
    String? phone,
    String? locale,
  }) async {
    calls.add('invite:${phone ?? email}');
    return {
      'invitation': {'id': 'fri_9', 'status': 'pending'},
      'share': {'text': 'Hi', 'link': 'https://x/y', 'subject': 's'},
      if (inviteDelivery.isNotEmpty) 'delivery': inviteDelivery,
    };
  }

  Object? defaultShare;
  Object? savedDefault = 'unset';

  @override
  Future<Map<String, dynamic>> updateSocialSettings(Object? share) async {
    savedDefault = share;
    defaultShare = share;
    return {};
  }

  @override
  Future<Map<String, dynamic>> socialSettings() async => {
    'defaultShare': defaultShare,
    'inviteCode': 'AB12CD34',
    'hasCompany': true,
    'publicProfile': publicProfile,
    'blocked': [],
  };
  @override
  Future<Map<String, dynamic>> follow(String userId) async {
    calls.add('follow:$userId');
    conn = {
      ...conn,
      'followers': [],
      'friends': [
        ...(conn['friends'] as List),
        {'id': userId, 'displayName': 'Cy Juma', 'relationship': 'friends'},
      ],
    };
    return {};
  }

  @override
  Future<Map<String, dynamic>> findPeople({String? q, String? code}) async {
    calls.add('find:${q ?? ''}:${code ?? ''}');
    return {
      'people': [
        {'id': 'dee', 'displayName': 'Dee Kweka', 'relationship': 'none'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> myGroups() async => {'groups': groups};
  @override
  Future<Map<String, dynamic>> discoverGroups({String q = ''}) async => {
    'groups': [
      {
        'id': 'g_open',
        'name': 'Dar Runners',
        'joinPolicy': 'open',
        'discoverable': true,
        'memberCount': 12,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> joinGroup({
    String? groupId,
    String? inviteCode,
  }) async {
    calls.add('join:${groupId ?? ''}:${inviteCode ?? ''}');
    return {
      'group': {
        'id': groupId ?? 'g_code',
        'name': 'Club',
        'you': {'role': 'member', 'status': 'active'},
      },
    };
  }

  @override
  Future<Map<String, dynamic>> sharedActivity(String id) async => {
    'item': id == 'mine'
        ? {..._item(id: id, owner: 'me', mine: true), 'views': 42}
        : _item(id: id),
    'comments': [
      {
        'id': 'c1',
        'text': 'Strong pace!',
        'createdAt': '2026-09-25T06:00:00.000Z',
        'author': {'id': 'ana', 'displayName': 'Ana'},
        'canDelete': true,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> addComment(String id, String text) async {
    calls.add('comment:$id:$text');
    return {};
  }

  @override
  Future<Map<String, dynamic>> groupDetail(
    String id, {
    String? scope,
    String? gymId,
  }) async => {
    'group': {
      'id': id,
      'name': 'PT clients',
      'joinPolicy': 'approval',
      'memberCount': 1,
      'inviteCode': 'ZX98YW76',
      'canManage': scope == null,
    },
    'members': [
      {
        'id': 'ben',
        'displayName': 'Ben Mushi',
        'role': 'member',
        'status': 'active',
      },
      {
        'id': 'cy',
        'displayName': 'Cy Juma',
        'role': 'member',
        'status': 'pending',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> groupMemberAction(
    String id,
    String userId,
    String action, {
    String? scope,
    String? gymId,
  }) async {
    calls.add('member:$scope:$userId:$action');
    return {};
  }

  @override
  Future<Map<String, dynamic>> shareActivity(
    String activityId,
    Object? shareWith,
  ) async {
    calls.add('share:$activityId:$shareWith');
    return {'activityId': activityId, 'shareWith': shareWith};
  }
}

Widget _app(ApiClient api, Widget child, {MemberData? data}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale(),
    child: MaterialApp(
      theme: buildTheme(),
      supportedLocales: const [Locale('en'), Locale('sw')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MemberDataScope(data: data ?? MemberData(), child: child),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  test('models: private is null; share round-trips', () {
    expect(ShareWith.fromJson(null), isNull);
    expect(
      ShareWith.fromJson({'followers': false, 'groups': [], 'company': false}),
      isNull,
    );
    final s = ShareWith.fromJson({
      'followers': true,
      'groups': ['g1'],
      'company': false,
    })!;
    expect(s.groups, ['g1']);
    expect(
      s.followers,
      isTrue,
      reason: 'stored followers now means everyone who follows',
    );
    expect(ShareWith.wire(s), {
      'v': 2,
      'friends': false,
      'followers': true,
      'public': false,
      'groups': ['g1'],
      'company': false,
      'allGroups': false,
    });
    expect(ShareWith.wire(const ShareWith()), isNull);
    final item = FeedItem.fromJson(_item());
    expect(item.owner.relationship, Relationship.friends);
    expect(item.activity.distanceKm, 5.2);
    expect(Relationship.fromWire('follows_you'), Relationship.followsYou);
    final g = SocialGroup.fromJson({
      'id': 'g',
      'name': 'X',
      'you': {'role': 'admin', 'status': 'pending'},
    });
    expect(g.isPending, isTrue);
  });

  test('a manual log sends who can see it only when chosen', () {
    final base = ManualActivityDraft(
      type: ActivityType.walking,
      startedAt: DateTime(2026, 9, 25),
      steps: 100,
    );
    expect(
      base.toJson().containsKey('shareWith'),
      isFalse,
      reason: 'left out: the default applies',
    );
    final private = ManualActivityDraft(
      type: ActivityType.walking,
      startedAt: DateTime(2026, 9, 25),
      steps: 100,
      shareChosen: true,
    );
    expect(private.toJson()['shareWith'], isNull);
    expect(private.toJson().containsKey('shareWith'), isTrue);
  });

  testWidgets('feed: what friends shared, with kudos', (tester) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(_app(api, const MemberCommunityPage()));
    await tester.pumpAndSettle();
    expect(find.text('Ben Mushi'), findsOneWidget);
    expect(find.text('Morning run'), findsOneWidget);
    expect(find.textContaining('5.20 km'), findsOneWidget);
    expect(find.textContaining('5:23 /km'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kudos-a1')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('kudos:a1:true'));
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('empty feed explains how to start', (tester) async {
    final api = _Api()..feedItems = [];
    await tester.pumpWidget(_app(api, const MemberCommunityPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feed-empty')), findsOneWidget);
  });

  testWidgets(
    'people: no invite-code card, follow back, search by name, contact picker button',
    (tester) async {
      _tall(tester);
      final api = _Api();
      await tester.pumpWidget(
        _app(api, const MemberCommunityPage(initialTab: 2)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-invite-code')), findsNothing);
      expect(find.byKey(const Key('people-pick-contact')), findsOneWidget);
      expect(find.text('Follow back'), findsOneWidget);
      await tester.tap(find.byKey(const Key('follow-cy')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('follow:cy'));
      expect(find.text('Follow back'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('people-search')),
        'QW12ER34',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        api.calls,
        contains('find:QW12ER34:'),
        reason: 'a name search; invite codes are no longer searched',
      );
      expect(find.text('Dee Kweka'), findsOneWidget);
    },
  );

  testWidgets('sent requests show the number you invited', (tester) async {
    _tall(tester);
    final api = _Api()
      ..outgoing = [
        {
          'id': 'fri_1',
          'status': 'pending',
          'contactType': 'phone',
          'contact': '+255650387211',
          'name': null,
        },
      ];
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 2)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sent-fri_1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('+255650387211'), findsOneWidget);
  });

  testWidgets('invite by number: FitFlex sends it when SMS is on', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api()
      ..lookupDelivery = {'sms': true, 'whatsapp': false}
      ..inviteDelivery = {'sms': 'sent'};
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 2)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('people-search')),
      '0650387211',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('FitFlex will send the invitation'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('friend-invite-share')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('invite:0650387211'));
    expect(find.textContaining('Invitation sent by SMS'), findsOneWidget);
  });

  testWidgets('sent requests say how FitFlex sent them', (tester) async {
    _tall(tester);
    final api = _Api()
      ..outgoing = [
        {
          'id': 'fri_a',
          'status': 'pending',
          'contactType': 'phone',
          'contact': '+255650387211',
          'sentBy': ['whatsapp'],
          'sentAt': '2026-10-17T08:00:00.000Z',
        },
        {
          'id': 'fri_b',
          'status': 'pending',
          'contactType': 'phone',
          'contact': '+255650387299',
          'sentBy': ['whatsapp', 'sms'],
          'whatsappFailed': true,
          'sentAt': '2026-10-17T08:00:00.000Z',
        },
      ];
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 2)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sent-fri_b')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Sent by FitFlex on WhatsApp'), findsOneWidget);
    expect(
      find.textContaining('Not on WhatsApp, so FitFlex sent an SMS'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a sent SMS shows what the provider later reported, if anything',
    (tester) async {
      _tall(tester);
      Map<String, dynamic> sms(String id, String? delivery) => {
        'id': id,
        'status': 'pending',
        'contactType': 'phone',
        'contact': '+2556503872$id',
        'sentBy': ['sms'],
        'sentAt': '2026-10-17T08:00:00.000Z',
        'smsDelivery': ?delivery,
      };
      final api = _Api()
        ..outgoing = [
          sms('11', 'delivered'),
          sms('22', 'undelivered'),
          sms('33', null),
          sms('44', 'pending'),
        ];
      await tester.pumpWidget(
        _app(api, const MemberCommunityPage(initialTab: 2)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('sent-44')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('SMS delivered'), findsOneWidget);
      expect(find.textContaining('SMS could not be delivered'), findsOneWidget);
      // Not reported yet, or only pending: no claim either way.
      expect(find.textContaining('Sent by FitFlex by SMS'), findsNWidgets(4));
    },
  );

  testWidgets(
    'invite where FitFlex could not send: says why, then the share sheet',
    (tester) async {
      _tall(tester);
      final api = _Api()
        ..lookupDelivery = {'sms': true, 'whatsapp': true}
        ..inviteDelivery = {
          'whatsapp': 'skipped:whatsapp_not_available',
          'sms': 'skipped:sms_not_configured',
        };
      await tester.pumpWidget(
        _app(api, const MemberCommunityPage(initialTab: 2)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('people-search')),
        '0650387211',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('friend-invite-share')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('SMS is not set up yet.'), findsOneWidget);
      expect(
        find.textContaining('WhatsApp is not set up yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('groups: join a listed group, or by code', (tester) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 3)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dar Runners'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join:g_open:'));

    await tester.tap(find.byKey(const Key('group-join-code')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ask-text')), 'ZX98YW76');
    await tester.tap(find.byKey(const Key('ask-text-ok')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join::ZX98YW76'));
  });

  testWidgets('shared activity: comments and adding one', (tester) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(
      _app(api, const MemberSharedActivityPage(activityId: 'a1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Strong pace!'), findsOneWidget);
    expect(find.byKey(const Key('run-splits')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-input')), 'Nice one');
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('comment:a1:Nice one'));
  });

  testWidgets(
    'a trainer manages their group but is told they see no activity',
    (tester) async {
      _tall(tester);
      final api = _Api();
      await tester.pumpWidget(
        _app(api, const GroupPage(groupId: 'g1', scope: 'trainer')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ZX98YW76'), findsOneWidget);
      expect(
        find.textContaining('you don\'t see anyone\'s activity'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('approve-cy')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('member:trainer:cy:approve'));
    },
  );

  testWidgets('who can see this: pick friends, a group and the company', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api()
      ..groups = [
        {
          'id': 'g1',
          'name': 'Dar Runners',
          'memberCount': 3,
          'you': {'role': 'member', 'status': 'active'},
        },
      ];
    ({ShareWith? share, bool cancelled})? result;
    await tester.pumpWidget(
      _app(
        api,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await pickShare(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('never shared'), findsOneWidget);
    // Public needs a public profile first.
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('share-public')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const Key('share-friends')));
    await tester.tap(find.byKey(const Key('share-group-g1')));
    await tester.tap(find.byKey(const Key('share-company')));
    await tester.tap(find.byKey(const Key('share-done')));
    await tester.pumpAndSettle();
    expect(result!.cancelled, isFalse);
    expect(result!.share!.toJson(), {
      'v': 2,
      'friends': true,
      'followers': false,
      'public': false,
      'groups': ['g1'],
      'company': true,
      'allGroups': false,
    });
  });

  testWidgets('Explore shows public posts from people you don\'t follow', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feed-pub1')), findsOneWidget);
    expect(find.text('Not following'), findsOneWidget);
  });

  testWidgets(
    'a public profile: counts, public posts, Follow — no follow-back needed',
    (tester) async {
      _tall(tester);
      final api = _Api();
      await tester.pumpWidget(_app(api, const MemberPersonPage(userId: 'ben')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1200 followers'), findsOneWidget);
      expect(find.byKey(const Key('feed-pub1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('person-follow')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('follow:ben'));
    },
  );

  testWidgets(
    'your own post: views (anonymous) and who engaged, with Follow back',
    (tester) async {
      _tall(tester);
      final api = _Api();
      api.feedItems = [];
      await tester.pumpWidget(
        _app(api, const MemberSharedActivityPage(activityId: 'mine')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('engagement')), findsOneWidget);
      expect(find.text('42 views'), findsWidgets);
      expect(find.textContaining('Viewers stay anonymous'), findsOneWidget);
      expect(find.text('Juma Fan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('follow-back-fan')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('follow:fan'));
      expect(
        find.byKey(const Key('follow-back-ana')),
        findsNothing,
        reason: 'already friends',
      );
    },
  );

  testWidgets('public posting is available once the profile is public', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api()..publicProfile = true;
    ({ShareWith? share, bool cancelled})? result;
    await tester.pumpWidget(
      _app(
        api,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await pickShare(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-public')));
    await tester.tap(find.byKey(const Key('share-followers')));
    await tester.tap(find.byKey(const Key('share-done')));
    await tester.pumpAndSettle();
    expect(result!.share!.public, isTrue);
    expect(result!.share!.followers, isTrue);
    expect(result!.share!.friends, isFalse);
  });

  group('default audience for new activities', () {
    Future<_Api> pumpSection(WidgetTester tester, Object? stored) async {
      _tall(tester);
      final api = _Api()
        ..publicProfile = true
        ..defaultShare = stored
        ..groups = [
          {
            'id': 'g1',
            'name': 'Dar Runners',
            'memberCount': 3,
            'you': {'role': 'member', 'status': 'active'},
          },
        ];
      await tester.pumpWidget(
        _app(api, const SingleChildScrollView(child: SocialPrivacySection())),
      );
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('the server default reads Public · All my groups', (
      tester,
    ) async {
      await pumpSection(tester, {'public': true, 'allGroups': true});
      expect(find.text('Public · All my groups'), findsOneWidget);
    });

    testWidgets('choosing All my groups saves allGroups true', (tester) async {
      final api = await pumpSection(tester, {'public': true});
      await tester.tap(find.byKey(const Key('privacy-default-share')));
      await tester.pumpAndSettle();
      expect(
        find.text('Every group you are in, including groups you join later.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('share-all-groups')));
      await tester.pumpAndSettle();
      // Each group is covered, so it can't be picked separately.
      final g1 = tester.widget<CheckboxListTile>(
        find.byKey(const Key('share-group-g1')),
      );
      expect(g1.value, isTrue);
      expect(g1.onChanged, isNull);
      await tester.tap(find.byKey(const Key('share-done')));
      await tester.pumpAndSettle();
      expect(api.savedDefault, {
        'v': 2,
        'friends': false,
        'followers': false,
        'public': true,
        'groups': <String>[],
        'company': false,
        'allGroups': true,
      });
    });

    testWidgets('switching All my groups off round-trips allGroups false', (
      tester,
    ) async {
      final api = await pumpSection(tester, {
        'public': true,
        'allGroups': true,
      });
      await tester.tap(find.byKey(const Key('privacy-default-share')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('share-all-groups')))
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('share-all-groups')));
      await tester.tap(find.byKey(const Key('share-done')));
      await tester.pumpAndSettle();
      expect((api.savedDefault as Map)['allGroups'], isFalse);
      expect((api.savedDefault as Map)['public'], isTrue);
    });

    testWidgets('Only you switches everything off', (tester) async {
      final api = await pumpSection(tester, {
        'public': true,
        'allGroups': true,
      });
      await tester.tap(find.byKey(const Key('privacy-default-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-private')));
      await tester.tap(find.byKey(const Key('share-done')));
      await tester.pumpAndSettle();
      expect(api.savedDefault, isNull);
    });

    testWidgets('a single activity picker has no All my groups choice', (
      tester,
    ) async {
      _tall(tester);
      final api = _Api()
        ..groups = [
          {
            'id': 'g1',
            'name': 'Dar Runners',
            'memberCount': 3,
            'you': {'role': 'member', 'status': 'active'},
          },
        ];
      ({ShareWith? share, bool cancelled})? result;
      await tester.pumpWidget(
        _app(
          api,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await pickShare(
                  context,
                  initial: const ShareWith(allGroups: true),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-all-groups')), findsNothing);
      await tester.tap(find.byKey(const Key('share-done')));
      await tester.pumpAndSettle();
      expect(result!.share!.groups, ['g1']);
      expect(result!.share!.allGroups, isFalse);
    });
  });
}
