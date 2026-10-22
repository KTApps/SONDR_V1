import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/single_post_screen.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/profile/friend_status.dart';
import 'package:sondr/features/profile/other_profile_screen.dart';
import 'package:sondr/features/profile/profile_actions.dart';
import 'package:sondr/features/profile/profile_metrics.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/sondr_action.dart';

import 'tiny_png.dart';

const String me = 'me';
const String them = 'them';

Friendship _friendship({
  bool accepted = true,
  String requestedBy = me,
  String other = them,
}) => Friendship(
  id: Friendship.pairId(me, other),
  users: [me, other]..sort(),
  requestedBy: requestedBy,
  status: accepted ? FriendshipStatus.accepted : FriendshipStatus.pending,
  profiles: {
    other: const FriendIdentity(username: 'cass', displayName: 'Cass'),
  },
);

Post _milestonePost(int i, {bool photo = true}) => MilestonePost(
  id: 'm$i',
  authorUid: them,
  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
  createdAt: DateTime(2026, 10, i + 1),
  caption: null,
  photos: photo
      ? [PostPhoto(url: 'https://x/m$i.jpg', storagePath: 'p/m$i')]
      : const [],
  taskName: 'Piano',
  milestoneHours: 20 * (i + 1),
  totalHours: 20 * (i + 1),
);

Post _sessionPost(int i, {bool photo = true}) => SessionPost(
  id: 's$i',
  authorUid: them,
  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
  createdAt: DateTime(2026, 9, i + 1),
  caption: null,
  photos: photo
      ? [PostPhoto(url: 'https://x/s$i.jpg', storagePath: 'p/s$i')]
      : const [],
  taskName: 'Piano',
  sessionSeconds: 3600,
);

/// What the profile asked for, without a Firestore in the way.
class _FakeActions implements ProfileActions {
  final added = <({String uid, String handle})>[];
  final accepted = <String>[];
  final removed = <String>[];
  final blocked = <String>[];
  final unblocked = <String>[];

  @override
  Future<void> addFriend(String uid, {String handle = ''}) async =>
      added.add((uid: uid, handle: handle));
  @override
  Future<void> acceptRequest(String pairId) async => accepted.add(pairId);
  @override
  Future<void> removeFriend(String pairId) async => removed.add(pairId);
  @override
  Future<void> block({
    required String uid,
    required String handle,
    required String displayName,
  }) async => blocked.add(uid);
  @override
  Future<void> unblock(String uid) async => unblocked.add(uid);
}

void main() {
  group('where I stand with someone', () {
    FriendStatus statusWith({
      List<Friendship> friendships = const [],
      Set<String> blocked = const {},
    }) => friendStatusOf(
      myUid: me,
      theirUid: them,
      friendships: friendships,
      blockedUids: blocked,
    );

    test('nobody I have anything with is someone to add', () {
      expect(statusWith(), FriendStatus.none);
      // Somebody else's friendship is not ours.
      expect(
        statusWith(friendships: [_friendship(other: 'someone')]),
        FriendStatus.none,
      );
    });

    test('a request I sent is Requested, one they sent is Accept', () {
      expect(
        statusWith(friendships: [_friendship(accepted: false)]),
        FriendStatus.requested,
      );
      expect(
        statusWith(
          friendships: [_friendship(accepted: false, requestedBy: them)],
        ),
        FriendStatus.incoming,
      );
    });

    test('an accepted friendship is Friends, whoever asked', () {
      expect(statusWith(friendships: [_friendship()]), FriendStatus.accepted);
      expect(
        statusWith(friendships: [_friendship(requestedBy: them)]),
        FriendStatus.accepted,
      );
    });

    test('a block I placed outranks everything', () {
      expect(
        statusWith(friendships: [_friendship()], blocked: const {them}),
        FriendStatus.blockedByMe,
      );
      expect(statusWith(blocked: const {them}), FriendStatus.blockedByMe);
    });

    test('each state says and offers the right thing', () {
      expect(friendStatusLabel(FriendStatus.none), 'Add friend');
      expect(friendStatusLabel(FriendStatus.requested), 'Requested');
      expect(friendStatusLabel(FriendStatus.incoming), 'Accept');
      expect(friendStatusLabel(FriendStatus.accepted), 'Friends');
      expect(friendStatusLabel(FriendStatus.blockedByMe), 'Unblock');

      // Requested and Friends are states, not offers.
      expect(friendStatusIsActionable(FriendStatus.requested), isFalse);
      expect(friendStatusIsActionable(FriendStatus.accepted), isFalse);
      for (final s in [
        FriendStatus.none,
        FriendStatus.incoming,
        FriendStatus.blockedByMe,
      ]) {
        expect(friendStatusIsActionable(s), isTrue, reason: '$s');
      }

      // Only a friend sees what they have been doing.
      expect(friendStatusSeesContent(FriendStatus.accepted), isTrue);
      for (final s in [
        FriendStatus.none,
        FriendStatus.requested,
        FriendStatus.incoming,
        FriendStatus.blockedByMe,
      ]) {
        expect(friendStatusSeesContent(s), isFalse, reason: '$s');
      }
    });

    test('the friendship between us is the one the actions act on', () {
      final ours = _friendship();
      expect(
        friendshipWith(
          myUid: me,
          theirUid: them,
          friendships: [_friendship(other: 'someone'), ours],
        )?.id,
        ours.id,
      );
      expect(
        friendshipWith(myUid: me, theirUid: them, friendships: const []),
        isNull,
      );
    });
  });

  group('their profile', () {
    Future<void> pump(
      WidgetTester tester, {
      List<Friendship> friendships = const [],
      List<Post> posts = const [],
      List<String> friendUids = const [],
      List<Block> blocks = const [],
      _FakeActions? actions,
      PublicProfile? published = const PublicProfile(
        uid: them,
        handle: 'cass',
        displayName: 'Cass',
        hours: 41,
      ),
    }) async {
      final factoryBefore = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = factoryBefore);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            friendshipsProvider.overrideWith((ref) => Stream.value(friendships)),
            blockedAccountsProvider.overrideWith((ref) => Stream.value(blocks)),
            publicProfileProvider.overrideWith((ref, uid) async => published),
            profilePostsProvider.overrideWith((ref, uid) async => posts),
            friendUidsProvider.overrideWith((ref, uid) async => friendUids),
            if (actions != null)
              profileActionsProvider.overrideWithValue(actions),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const OtherProfileScreen(uid: them),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a stranger: the handle, the hours, and a way in', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('cass'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('hours'), findsOneWidget);
      expect(find.text('Add friend'), findsOneWidget);
      expect(
        find.text('Add each other as friends to see posts and milestones.'),
        findsOneWidget,
      );
      // Nothing of theirs: no sections, no counts, no photo in the ring.
      expect(find.text('Friends'), findsNothing);
      expect(find.text('Milestones'), findsNothing);
      expect(find.text('Posts'), findsNothing);
      expect(find.text('milestones'), findsNothing);
      expect(find.byType(SondrPhoto), findsNothing);
      // Their initial instead.
      expect(find.text('C'), findsOneWidget);
      // Removing a friend you do not have is not offered; blocking is.
      expect(find.text('Remove friend'), findsNothing);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('someone who has blocked me is a stranger, exactly', (
      tester,
    ) async {
      // What a block leaves behind: no friendship, and nothing in any
      // audience. The page must not differ from the stranger above.
      await pump(tester, friendships: const [], posts: const []);
      expect(find.text('Add friend'), findsOneWidget);
      expect(
        find.text('Add each other as friends to see posts and milestones.'),
        findsOneWidget,
      );
      expect(find.text('Milestones'), findsNothing);
      expect(find.text('Posts'), findsNothing);
    });

    testWidgets('a request I sent reads Requested and does nothing', (
      tester,
    ) async {
      await pump(tester, friendships: [_friendship(accepted: false)]);
      final action = tester.widget<SondrAction>(
        find.widgetWithText(SondrAction, 'Requested'),
      );
      expect(action.onPressed, isNull);
      expect(find.text('Milestones'), findsNothing);
    });

    testWidgets('a friend: hours, shared milestones, and the three sections', (
      tester,
    ) async {
      await pump(
        tester,
        friendships: [_friendship()],
        posts: [_milestonePost(0), _milestonePost(1), _sessionPost(0)],
        friendUids: const ['a', 'b'],
      );
      // Hours, and milestones they have SHARED: two posts.
      expect(find.widgetWithText(ProfileStat, '41'), findsOneWidget);
      expect(find.text('hours'), findsOneWidget);
      expect(find.widgetWithText(ProfileStat, '2'), findsOneWidget);
      expect(find.text('milestones'), findsOneWidget);
      // Three sections, each with its count beside it.
      expect(find.widgetWithText(ProfileHeading, 'Friends'), findsOneWidget);
      expect(find.widgetWithText(ProfileHeading, 'Milestones'), findsOneWidget);
      expect(find.widgetWithText(ProfileHeading, 'Posts'), findsOneWidget);
      expect(find.widgetWithText(ProfileHeading, '2'), findsNWidgets(2),
          reason: 'two friends, two milestones');
      expect(find.widgetWithText(ProfileHeading, '3'), findsOneWidget,
          reason: 'all three posts');
      // The invitation is for people who are not friends.
      expect(
        find.text('Add each other as friends to see posts and milestones.'),
        findsNothing,
      );
      // Two strips: two milestone tiles and three post tiles.
      expect(find.byType(ProfileStripTile), findsNWidgets(5));
      // The newest shared milestone photo is in the ring, not their initial.
      expect(find.text('C'), findsNothing);
      expect(
        find.widgetWithText(SondrAction, 'Friends'),
        findsOneWidget,
        reason: 'the status, beside the heading of the same name',
      );
      expect(find.text('Remove friend'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('a post with no photo is counted and not pictured', (
      tester,
    ) async {
      await pump(
        tester,
        friendships: [_friendship()],
        posts: [_milestonePost(0, photo: false), _sessionPost(0)],
      );
      // One milestone, two posts — and one tile, in the Posts strip only.
      expect(find.widgetWithText(ProfileHeading, '1'), findsOneWidget);
      expect(find.widgetWithText(ProfileHeading, '2'), findsOneWidget);
      expect(find.widgetWithText(ProfileStat, '1'), findsOneWidget);
      expect(find.byType(ProfileStripTile), findsNWidgets(1));
    });

    testWidgets('a hundred posts is where the count stops counting', (
      tester,
    ) async {
      expect(profileCountLabel(99), '99');
      expect(profileCountLabel(100), '100+');
      await pump(
        tester,
        friendships: [_friendship()],
        posts: [for (var i = 0; i < 100; i++) _sessionPost(i, photo: false)],
      );
      expect(find.widgetWithText(ProfileHeading, '100+'), findsOneWidget);
    });

    testWidgets('Remove friend asks first, and Cancel changes nothing', (
      tester,
    ) async {
      await pump(tester, friendships: [_friendship()]);
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      expect(find.text('Remove friend?'), findsOneWidget);
      expect(find.text(removeFriendBody('cass')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Remove friend?'), findsNothing);
      // Still their friend.
      expect(find.text('Friends'), findsWidgets);
    });

    testWidgets('Block asks first, naming what it does', (tester) async {
      await pump(tester, friendships: [_friendship()]);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(find.text('Block this person?'), findsOneWidget);
      expect(find.textContaining('taken out of the posts'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Block this person?'), findsNothing);
    });

    testWidgets('someone I blocked shows nothing of theirs, and Unblock', (
      tester,
    ) async {
      await pump(
        tester,
        friendships: const [],
        blocks: const [
          Block(blocker: me, blocked: them, username: 'cass', displayName: 'Cass'),
        ],
        posts: [_milestonePost(0)],
      );
      expect(find.text('Unblock'), findsOneWidget);
      expect(find.text('Milestones'), findsNothing);
      expect(find.byType(ProfileStripTile), findsNothing);
      // Blocking again is not offered.
      expect(find.text('Block'), findsNothing);
    });

    testWidgets('a handle from the entry point stands in until one is published', (
      tester,
    ) async {
      // Nothing published, no friendship: all the page has is what the
      // byline that opened it knew. That is enough to be somebody.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            friendshipsProvider.overrideWith(
              (ref) => Stream.value(const <Friendship>[]),
            ),
            blockedAccountsProvider.overrideWith(
              (ref) => Stream.value(const <Block>[]),
            ),
            publicProfileProvider.overrideWith((ref, uid) async => null),
            profilePostsProvider.overrideWith((ref, uid) async => const []),
            friendUidsProvider.overrideWith((ref, uid) async => const []),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const OtherProfileScreen(
              uid: them,
              handle: 'cass',
              displayName: 'Cass',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('cass'), findsOneWidget);
      expect(find.text('Someone'), findsNothing);
      // Their initial in the ring, from the name we were handed.
      expect(find.text('C'), findsOneWidget);
      // Hours are unknown, which is not zero: no figure at all.
      expect(find.text('0'), findsNothing);
      expect(find.text('hours'), findsNothing);
    });

    testWidgets('a page nobody could name says Someone, and no hours', (
      tester,
    ) async {
      await pump(tester, published: null);
      expect(find.text('Someone'), findsOneWidget);
      expect(find.text('hours'), findsNothing);
      expect(find.byType(ProfileStat), findsNothing);
    });

    testWidgets('a friendship names them when nothing is published', (
      tester,
    ) async {
      await pump(tester, published: null, friendships: [_friendship()]);
      expect(find.text('cass'), findsOneWidget);
      expect(find.text('Someone'), findsNothing);
      // A friend with no published copy: milestones still count, hours
      // stay unknown.
      expect(find.text('hours'), findsNothing);
      expect(find.widgetWithText(ProfileStat, '0'), findsOneWidget,
          reason: 'no shared milestones yet');
      expect(find.text('milestones'), findsOneWidget);
    });

    testWidgets('a published handle wins over the one we were handed', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            friendshipsProvider.overrideWith(
              (ref) => Stream.value(const <Friendship>[]),
            ),
            blockedAccountsProvider.overrideWith(
              (ref) => Stream.value(const <Block>[]),
            ),
            publicProfileProvider.overrideWith(
              (ref, uid) async => const PublicProfile(
                uid: them,
                handle: 'renamed',
                displayName: 'Renamed',
                hours: 12,
              ),
            ),
            profilePostsProvider.overrideWith((ref, uid) async => const []),
            friendUidsProvider.overrideWith((ref, uid) async => const []),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const OtherProfileScreen(
              uid: them,
              handle: 'stale',
              displayName: 'Stale',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('renamed'), findsOneWidget);
      expect(find.text('stale'), findsNothing);
      expect(find.widgetWithText(ProfileStat, '12'), findsOneWidget);
    });

    testWidgets('Add friend works on a profile that has published nothing', (
      tester,
    ) async {
      // The bug: the page had no handle to offer, so the request was
      // refused for want of one — search's rule, applied where a uid is
      // the address.
      final acts = _FakeActions();
      await pump(tester, published: null, actions: acts);
      await tester.tap(find.text('Add friend'));
      await tester.pumpAndSettle();
      expect(acts.added, hasLength(1));
      expect(acts.added.single.uid, them);
      // And never search's validation copy.
      expect(find.text('Enter a handle.'), findsNothing);
    });

    testWidgets('Add friend carries the handle when the page knows one', (
      tester,
    ) async {
      final acts = _FakeActions();
      await pump(tester, actions: acts);
      await tester.tap(find.text('Add friend'));
      await tester.pumpAndSettle();
      expect(acts.added.single.uid, them);
      expect(acts.added.single.handle, 'cass');
    });

    testWidgets('Accept answers the request this page is about', (
      tester,
    ) async {
      final acts = _FakeActions();
      final f = _friendship(accepted: false, requestedBy: them);
      await pump(tester, friendships: [f], actions: acts, published: null);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(acts.accepted, [f.id]);
    });

    testWidgets('Remove and Unblock act on the uid, not on a handle', (
      tester,
    ) async {
      final acts = _FakeActions();
      final f = _friendship();
      await pump(tester, friendships: [f], actions: acts, published: null);
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(acts.removed, [f.id]);
    });

    testWidgets('the rules sit inside the gutter, as they do on my own page', (
      tester,
    ) async {
      await pump(tester, friendships: [_friendship()], posts: [_sessionPost(0)]);
      final scale = figmaScale(
        tester.element(find.byType(OtherProfileScreen)),
      );
      final width = tester.getSize(find.byType(OtherProfileScreen)).width;
      final lines = find.byType(ProfileHairline);
      expect(lines, findsWidgets);
      // By index: every ProfileHairline is the same const instance, so
      // byWidget finds them all at once.
      for (var i = 0; i < lines.evaluate().length; i++) {
        final rect = tester.getRect(lines.at(i));
        expect(rect.left, closeTo(kProfileGutter * scale, 0.5));
        expect(rect.right, closeTo(width - kProfileGutter * scale, 0.5));
        expect(rect.height, 1, reason: 'a hairline is a hairline');
      }
    });

    testWidgets('accepting fills the Friends section in, with no relaunch', (
      tester,
    ) async {
      // The real friendUidsProvider, with only its READ faked: before they
      // accept, the mirror is refused (empty); after, it answers. Nothing
      // is re-pumped from scratch — the page is the same page.
      final factoryBefore = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = factoryBefore);
      final friendships = StreamController<List<Friendship>>();
      addTearDown(friendships.close);
      var mirror = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            friendshipsProvider.overrideWith((ref) => friendships.stream),
            blockedAccountsProvider.overrideWith(
              (ref) => Stream.value(const <Block>[]),
            ),
            publicProfileProvider.overrideWith(
              (ref, uid) async => const PublicProfile(
                uid: them,
                handle: 'cass',
                displayName: 'Cass',
                hours: 41,
              ),
            ),
            profilePostsProvider.overrideWith((ref, uid) async => const []),
            friendMirrorReaderProvider.overrideWithValue(
              (uid, source) async => mirror,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const OtherProfileScreen(uid: them),
          ),
        ),
      );
      friendships.add([_friendship(accepted: false, requestedBy: them)]);
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsOneWidget);
      expect(find.widgetWithText(ProfileHeading, 'Friends'), findsNothing);

      // They are friends now, and their mirror answers.
      mirror = ['a', 'b'];
      friendships.add([_friendship()]);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ProfileHeading, 'Friends'), findsOneWidget);
      expect(find.widgetWithText(ProfileHeading, '2'), findsOneWidget);
    });

    testWidgets('nothing is painted until everything is known', (tester) async {
      final factoryBefore = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = factoryBefore);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            friendshipsProvider.overrideWith(
              (ref) => Stream.value([_friendship()]),
            ),
            blockedAccountsProvider.overrideWith(
              (ref) => Stream.value(const <Block>[]),
            ),
            // Their published profile never arrives. A completer, not a
            // delay: a pending timer outlives the test.
            publicProfileProvider.overrideWith(
              (ref, uid) => Completer<PublicProfile?>().future,
            ),
            profilePostsProvider.overrideWith((ref, uid) async => [
                  _milestonePost(0),
                ]),
            friendUidsProvider.overrideWith((ref, uid) async => const ['a']),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const OtherProfileScreen(uid: them),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Not a half-built page: nothing at all. Not even Back.
      expect(find.text('cass'), findsNothing);
      expect(find.byType(ProfileHeading), findsNothing);
      expect(find.byType(ProfileStripTile), findsNothing);
      expect(find.byType(SondrAction), findsNothing);
    });
  });

  group('their friends list', () {
    Future<void> pumpList(WidgetTester tester, {List<String> uids = const ['a', 'b']}) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            publicProfileProvider.overrideWith(
              (ref, uid) async => PublicProfile(
                uid: uid,
                handle: 'cass',
                displayName: 'Cass',
                hours: 3,
              ),
            ),
            friendUidsProvider.overrideWith((ref, uid) async => uids),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendsOfScreen(uid: them, handle: 'ada'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names nobody — you arrived by tapping Friends', (
      tester,
    ) async {
      await pumpList(tester);
      expect(find.text('ada’s friends'), findsNothing);
      expect(find.textContaining('friends'), findsNothing);
    });

    testWidgets('and the first row has not moved', (tester) async {
      // Measured on a 13 Pro with the title still there (135.786), before
      // it was replaced with its own height in empty space.
      await pumpList(tester);
      expect(tester.getRect(find.text('cass').first).top, closeTo(135.79, 0.5));
    });
  });

  group('one post on its own page', () {
    testWidgets('the card, its actions, and the way back', (tester) async {
      final factoryBefore = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = factoryBefore);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentUidProvider.overrideWithValue(me)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: SinglePostScreen(post: _milestonePost(0)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SinglePostScreen), findsOneWidget);
      // The feed's own card, with its byline and its two actions.
      expect(find.text('Cass'), findsOneWidget);
      expect(find.text('Like'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });
  });
}
