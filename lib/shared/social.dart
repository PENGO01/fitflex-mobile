/// Sharing activities between members: people, the feed, comments, groups.
///
/// Who sees a shared activity: friends (you follow each other), followers
/// (anyone who follows you), everyone (public, with a public profile),
/// members of chosen groups, and colleagues at the same company. New
/// activities follow the member's default, which starts as public and all
/// their groups; the member can change or switch it off.
library;

import 'i18n.dart';

/// Who one activity is shared with. `null` everywhere means private.
class ShareWith {
  const ShareWith({
    this.friends = false,
    this.followers = false,
    this.public = false,
    this.groups = const [],
    this.company = false,
    this.allGroups = false,
  });

  /// You follow each other.
  final bool friends;

  /// Anyone who follows you (no follow-back needed).
  final bool followers;

  /// Any member (needs a public profile).
  final bool public;
  final List<String> groups;
  final bool company;

  /// Every group the member is in, including ones joined later. Only used
  /// for the default audience; one activity names its groups in [groups].
  final bool allGroups;

  bool get isPrivate =>
      !friends &&
      !followers &&
      !public &&
      groups.isEmpty &&
      !company &&
      !allGroups;

  static ShareWith? fromJson(Object? v) {
    if (v is! Map) return null;
    final s = ShareWith(
      friends: v['friends'] == true,
      followers: v['followers'] == true,
      public: v['public'] == true,
      groups: [
        for (final g in (v['groups'] as List? ?? const [])) g.toString(),
      ],
      company: v['company'] == true,
      allGroups: v['allGroups'] == true,
    );
    return s.isPrivate ? null : s;
  }

  /// `v: 2` tells the server `followers` means everyone who follows you
  /// (older app builds used it for friends). `allGroups` is always sent:
  /// the server reads a missing value as false.
  Map<String, dynamic> toJson() => {
    'v': 2,
    'friends': friends,
    'followers': followers,
    'public': public,
    'groups': groups,
    'company': company,
    'allGroups': allGroups,
  };

  /// The JSON to send: null for private.
  static Object? wire(ShareWith? s) =>
      s == null || s.isPrivate ? null : s.toJson();

  @override
  bool operator ==(Object other) =>
      other is ShareWith &&
      other.friends == friends &&
      other.followers == followers &&
      other.public == public &&
      other.company == company &&
      other.allGroups == allGroups &&
      other.groups.length == groups.length &&
      other.groups.toSet().containsAll(groups);

  @override
  int get hashCode => Object.hash(
    friends,
    followers,
    public,
    company,
    allGroups,
    Object.hashAllUnordered(groups),
  );
}

enum Relationship {
  you('you'),
  friends('friends'),
  following('following'),
  followsYou('follows_you'),
  none('none');

  const Relationship(this.wire);
  final String wire;

  static Relationship fromWire(Object? v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => Relationship.none);
}

class SocialPerson {
  const SocialPerson({
    required this.id,
    this.displayName,
    this.username,
    this.relationship = Relationship.none,
  });

  final String id;
  final String? displayName;

  /// The member's username when they have one (the server then also puts it
  /// in [displayName], so older builds already show it).
  final String? username;
  final Relationship relationship;

  /// "@amina_k" when there is a username, otherwise the name.
  String get name {
    final u = (username ?? '').trim();
    if (u.isNotEmpty) return '@$u';
    return (displayName ?? '').trim().isEmpty
        ? FFLocale.text('social.memberName')
        : displayName!.trim();
  }

  factory SocialPerson.fromJson(Map json) => SocialPerson(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String?,
    username: json['username'] as String?,
    relationship: Relationship.fromWire(json['relationship']),
  );
}

/// A shared activity as others see it (never calories or the route).
class SharedActivity {
  const SharedActivity({
    required this.id,
    required this.type,
    required this.startedAt,
    this.title,
    this.durationMinutes,
    this.distanceKm,
    this.steps,
    this.movingSeconds,
    this.elevationGainM,
    this.splits = const [],
  });

  final String id;
  final String type;
  final DateTime startedAt;
  final String? title;
  final int? durationMinutes;
  final double? distanceKm;
  final int? steps;
  final int? movingSeconds;
  final double? elevationGainM;
  final List<int> splits;

  factory SharedActivity.fromJson(Map json) => SharedActivity(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'other',
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    title: json['title'] as String?,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    steps: (json['steps'] as num?)?.toInt(),
    movingSeconds: (json['movingSeconds'] as num?)?.toInt(),
    elevationGainM: (json['elevationGainM'] as num?)?.toDouble(),
    splits: [
      for (final s in (json['splits'] as List? ?? const []))
        if (s is num) s.toInt(),
    ],
  );
}

class FeedItem {
  const FeedItem({
    required this.activity,
    required this.owner,
    this.kudos = 0,
    this.youKudoed = false,
    this.comments = 0,
    this.views,
    this.sharedWith,
  });

  final SharedActivity activity;
  final SocialPerson owner;
  final int kudos;
  final bool youKudoed;
  final int comments;

  /// How many people opened it — only on your own items.
  final int? views;

  /// Only on your own items.
  final ShareWith? sharedWith;

  FeedItem copyWith({int? kudos, bool? youKudoed, int? comments}) => FeedItem(
    activity: activity,
    owner: owner,
    kudos: kudos ?? this.kudos,
    youKudoed: youKudoed ?? this.youKudoed,
    comments: comments ?? this.comments,
    views: views,
    sharedWith: sharedWith,
  );

  factory FeedItem.fromJson(Map json) => FeedItem(
    activity: SharedActivity.fromJson(json['activity'] as Map? ?? const {}),
    owner: SocialPerson.fromJson(json['owner'] as Map? ?? const {}),
    kudos: (json['kudos'] as num?)?.toInt() ?? 0,
    youKudoed: json['youKudoed'] == true,
    comments: (json['comments'] as num?)?.toInt() ?? 0,
    views: (json['views'] as num?)?.toInt(),
    sharedWith: ShareWith.fromJson(json['sharedWith']),
  );
}

class SocialComment {
  const SocialComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
    this.canDelete = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final SocialPerson author;
  final bool canDelete;

  factory SocialComment.fromJson(Map json) => SocialComment(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    author: SocialPerson.fromJson(json['author'] as Map? ?? const {}),
    canDelete: json['canDelete'] == true,
  );
}

class SocialGroup {
  const SocialGroup({
    required this.id,
    required this.name,
    this.description,
    this.ownerType = 'member',
    this.joinPolicy = 'approval',
    this.discoverable = false,
    this.memberCount = 0,
    this.role,
    this.status,
    this.inviteCode,
    this.canManage = false,
    this.pending = 0,
  });

  final String id;
  final String name;
  final String? description;

  /// member | trainer | gym | corporate
  final String ownerType;

  /// open | approval
  final String joinPolicy;
  final bool discoverable;
  final int memberCount;

  /// Your place in it, if any: admin | member, active | pending.
  final String? role;
  final String? status;

  /// Shown to people who manage the group.
  final String? inviteCode;
  final bool canManage;

  /// Requests waiting (for owners).
  final int pending;

  bool get isMember => status == 'active';
  bool get isPending => status == 'pending';

  factory SocialGroup.fromJson(Map json) {
    final you = json['you'] is Map ? json['you'] as Map : const {};
    return SocialGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      ownerType: json['ownerType'] as String? ?? 'member',
      joinPolicy: json['joinPolicy'] as String? ?? 'approval',
      discoverable: json['discoverable'] == true,
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      role: you['role'] as String?,
      status: you['status'] as String?,
      inviteCode: json['inviteCode'] as String?,
      canManage: json['canManage'] == true,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.id,
    this.displayName,
    this.username,
    this.role = 'member',
    this.status = 'active',
  });

  final String id;
  final String? displayName;
  final String? username;
  final String role;
  final String status;

  /// "@amina_k" when there is a username, otherwise the name.
  String get name {
    final u = (username ?? '').trim();
    if (u.isNotEmpty) return '@$u';
    return (displayName ?? '').trim().isEmpty
        ? FFLocale.text('social.memberName')
        : displayName!.trim();
  }

  factory GroupMember.fromJson(Map json) => GroupMember(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String?,
    username: json['username'] as String?,
    role: json['role'] as String? ?? 'member',
    status: json['status'] as String? ?? 'active',
  );
}

class SocialSettings {
  const SocialSettings({
    this.defaultShare,
    this.publicProfile = false,
    this.inviteCode = '',
    this.hasCompany = false,
    this.blocked = const [],
  });

  final ShareWith? defaultShare;

  /// Findable by name by anyone, with a profile of public posts and a
  /// place in Explore. On by default; the member can switch it off.
  final bool publicProfile;
  final String inviteCode;
  final bool hasCompany;
  final List<SocialPerson> blocked;

  factory SocialSettings.fromJson(Map json) => SocialSettings(
    defaultShare: ShareWith.fromJson(json['defaultShare']),
    publicProfile: json['publicProfile'] == true,
    inviteCode: json['inviteCode'] as String? ?? '',
    hasCompany: json['hasCompany'] == true,
    blocked: [
      for (final b in (json['blocked'] as List? ?? const []))
        if (b is Map) SocialPerson.fromJson(b),
    ],
  );
}

/// Someone's profile as you see it.
class SocialProfile {
  const SocialProfile({
    required this.person,
    this.publicProfile = false,
    this.followers = 0,
    this.following = 0,
    this.items = const [],
    this.next,
  });

  final SocialPerson person;
  final bool publicProfile;
  final int followers;
  final int following;
  final List<FeedItem> items;
  final String? next;

  factory SocialProfile.fromJson(Map json) {
    final p = json['person'] as Map? ?? const {};
    return SocialProfile(
      person: SocialPerson.fromJson(p),
      publicProfile: p['publicProfile'] == true,
      followers: (p['followers'] as num?)?.toInt() ?? 0,
      following: (p['following'] as num?)?.toInt() ?? 0,
      items: [
        for (final i in (json['items'] as List? ?? const []))
          if (i is Map) FeedItem.fromJson(i),
      ],
      next: json['next'] as String?,
    );
  }
}

/// Who engaged with your post: a view count (viewers stay anonymous), and
/// the people who gave kudos or commented.
class Engagement {
  const Engagement({
    this.views = 0,
    this.kudos = const [],
    this.commenters = const [],
  });

  final int views;
  final List<SocialPerson> kudos;
  final List<SocialPerson> commenters;

  factory Engagement.fromJson(Map json) => Engagement(
    views: (json['views'] as num?)?.toInt() ?? 0,
    kudos: [
      for (final p in (json['kudos'] as List? ?? const []))
        if (p is Map) SocialPerson.fromJson(p),
    ],
    commenters: [
      for (final p in (json['commenters'] as List? ?? const []))
        if (p is Map) SocialPerson.fromJson(p),
    ],
  );
}
