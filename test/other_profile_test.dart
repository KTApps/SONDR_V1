import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/single_post_screen.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/profile/friend_status.dart';
import 'package:sondr/features/profile/other_profile_screen.dart';
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
