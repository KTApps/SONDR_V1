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
import 'package:sondr/features/reports/report.dart';
import 'package:sondr/features/reports/report_flow.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/sondr_action.dart';
import 'package:sondr/shared/sondr_error.dart';
import 'package:sondr/shared/sondr_notice.dart';

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
      // The line under the handle states what is TRUE...
      expect(friendStatusLabel(FriendStatus.none), '');
      expect(friendStatusLabel(FriendStatus.requested), 'Requested');
      expect(friendStatusLabel(FriendStatus.incoming), 'Wants to be friends');
      expect(friendStatusLabel(FriendStatus.accepted), 'Friends');
      expect(friendStatusLabel(FriendStatus.blockedByMe), 'Unblock');

      // ...and the bar's left slot offers what can be DONE.
      expect(friendActionLabel(FriendStatus.none), 'Add');
      expect(friendActionLabel(FriendStatus.incoming), 'Accept');
      expect(friendActionLabel(FriendStatus.accepted), 'Remove');
      expect(friendActionLabel(FriendStatus.requested), isNull);
      expect(friendActionLabel(FriendStatus.blockedByMe), isNull);

      // Only Unblock is an action in the line itself.
      expect(friendStatusIsActionable(FriendStatus.blockedByMe), isTrue);
      for (final s in [
        FriendStatus.none,
        FriendStatus.requested,
        FriendStatus.incoming,
        FriendStatus.accepted,
      ]) {
        expect(friendStatusIsActionable(s), isFalse, reason: '$s');
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
      Reports? reports,
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
      // Unmount anything a previous pump left behind, so a test that
      // pumps twice really gets two pages.
      await tester.pumpWidget(const SizedBox.shrink());
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
            if (reports != null) reportsProvider.overrideWithValue(reports),
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
      expect(find.text('Add'), findsOneWidget);
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
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('someone who has blocked me is a stranger, exactly', (
      tester,
    ) async {
      // What a block leaves behind: no friendship, and nothing in any
      // audience. The page must not differ from the stranger above.
      await pump(tester, friendships: const [], posts: const []);
      expect(find.text('Add'), findsOneWidget);
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
      // A state, not an offer: it sits in the subtitle's slot in the
      // quiet tone, and the bar's left slot is empty.
      final line = tester.widget<Text>(find.text('Requested'));
      expect(line.style?.color, const Color(0xFF6E6E6E));
      expect(find.text('Add'), findsNothing);
      expect(find.text('Accept'), findsNothing);
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
      // The stat's label — the milestone tiles' rings say "hours" too.
      expect(
        find.descendant(of: find.byType(ProfileStat), matching: find.text('hours')),
        findsOneWidget,
      );
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
        find.text('Friends'),
        findsNWidgets(2),
        reason: 'the status line, and the section heading of the same name',
      );
      expect(find.text('Remove'), findsOneWidget);
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
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove cass?'), findsOneWidget);
      expect(find.text(removeFriendBody('cass')), findsOneWidget);
      await tester.tap(find.text('Back').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Remove cass?'), findsNothing);
      // Still their friend.
      expect(find.text('Friends'), findsWidgets);
    });

    testWidgets('Block asks first, naming what it does', (tester) async {
      await pump(tester, friendships: [_friendship()]);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      // The slot asks which of the two first — reporting and blocking are
      // both "this person is a problem".
      expect(find.text('cass'), findsWidgets);
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      expect(find.text('Block cass?'), findsOneWidget);
      expect(
        find.text('They won\'t be able to see your profile or posts.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Block cass?'), findsNothing);
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
      await tester.tap(find.text('Add'));
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
      await tester.tap(find.text('Add'));
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
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      // The card's Remove, not the bar's.
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(acts.removed, [f.id]);
    });

    testWidgets('a friend\'s ring fills; a stranger\'s is the bare track', (
      tester,
    ) async {
      const filled = PublicProfile(
        uid: them,
        handle: 'cass',
        displayName: 'Cass',
        hours: 41,
        ringProgress: 0.6,
      );
      double ringFill(WidgetTester t) =>
          t.widget<ProgressRing>(find.byType(ProgressRing).first).progress;

      await pump(
        tester,
        friendships: [_friendship()],
        posts: [_milestonePost(0)],
        published: filled,
      );
      expect(ringFill(tester), closeTo(0.6, 0.001));

      // A stranger is not shown what they are working on.
      await pump(tester, friendships: const [], published: filled);
      expect(ringFill(tester), 0);
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

    testWidgets('a second tap on the bar never confirms', (tester) async {
      // The actions sit where muscle memory expects a tab. Tapping twice
      // — the way you would switch tabs and change your mind — must not
      // remove or block anyone. (The second tap lands on the card's
      // scrim, which dismisses it: a no, as it should be.)
      final acts = _FakeActions();
      await pump(tester, friendships: [_friendship()], actions: acts);
      for (final label in ['Remove', 'Block']) {
        final slot = tester.getRect(find.text(label).hitTestable()).center;
        await tester.tapAt(slot);
        await tester.pumpAndSettle();
        // Whatever the slot opened — a confirm for Remove, the
        // Report/Block sheet for Block — its own actions are nowhere
        // near the slot that opened it.
        expect(
          tester.getRect(find.text(label).hitTestable().last).contains(slot),
          isFalse,
          reason: '$label sits under its own slot',
        );
        await tester.tapAt(slot);
        await tester.pumpAndSettle();
      }
      expect(acts.removed, isEmpty, reason: 'a double tap removed them');
      expect(acts.blocked, isEmpty, reason: 'a double tap blocked them');
    });

    testWidgets('Block writes nothing until the card says so', (tester) async {
      final acts = _FakeActions();
      await pump(tester, friendships: [_friendship()], actions: acts);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(acts.blocked, isEmpty);
      await tester.tap(find.text('Back').hitTestable());
      await tester.pumpAndSettle();
      expect(acts.blocked, isEmpty);

      // Slot → the Report/Block sheet → Block → the confirm → blocked.
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      expect(acts.blocked, isEmpty, reason: 'the confirm still asks');
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      expect(acts.blocked, [them]);
    });

    testWidgets('the slot offers Report, Block and Cancel — no title', (
      tester,
    ) async {
      await pump(tester, friendships: [_friendship()]);
      final handlesBefore = find.text('cass').evaluate().length;
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();

      // Three actions and nothing else. The card carries no heading: the
      // handle is in the hero above it, and repeating it made the two
      // answers read as a subheading of their name.
      final card = find.ancestor(
        of: find.text('Report'),
        matching: find.byType(Material),
      );
      final labels = find
          .descendant(of: card.last, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      expect(labels, ['Report', 'Block', 'Back']);
      expect(
        find.text('cass').evaluate().length,
        handlesBefore,
        reason: 'the handle was repeated on the card',
      );
    });

    testWidgets('the sheet sits mid-screen, never under the slot', (
      tester,
    ) async {
      await pump(tester, friendships: [_friendship()]);
      final slot = tester.getRect(find.text('Block'));
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();

      final report = tester.getRect(find.text('Report'));
      final screen = tester.getSize(find.byType(OtherProfileScreen));
      // Centred: the three actions straddle the middle of the screen.
      expect(report.center.dy, lessThan(screen.height / 2));
      expect(
        tester.getRect(find.text('Back').hitTestable()).center.dy,
        greaterThan(screen.height / 2),
      );
      // And none of them is under the slot that opened the card.
      for (final label in ['Report', 'Block', 'Back']) {
        expect(
          slot.contains(tester.getRect(find.text(label).hitTestable().last).center),
          isFalse,
          reason: '$label sits under the slot',
        );
      }
    });

    testWidgets('Report asks why, thanks quietly, and hides nothing', (
      tester,
    ) async {
      final reports = _Reports();
      final acts = _FakeActions();
      await pump(
        tester,
        friendships: [_friendship()],
        actions: acts,
        reports: reports,
      );
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report cass'), findsOneWidget);
      await tester.tap(find.text('Something else'));
      await tester.pumpAndSettle();

      expect(reports.sent, ['user|$them|$them|other']);
      // Reporting a person hides nothing of theirs — blocking does that,
      // and it is a separate decision they did not make.
      expect(reports.hidden, isEmpty);
      expect(acts.blocked, isEmpty);

      // The thank-you, in the quiet tone rather than the error style.
      expect(find.text(kReportThanks), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SondrNotice),
          matching: find.text(kReportThanks),
        ),
        findsOneWidget,
      );
      // And it goes on its own.
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
      expect(find.text(kReportThanks), findsNothing);
    });

    testWidgets('a report that fails says so in the error style', (
      tester,
    ) async {
      final reports = _Reports(sends: false);
      await pump(tester, friendships: [_friendship()], reports: reports);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      expect(find.text(kReportFailed), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SondrError),
          matching: find.text(kReportFailed),
        ),
        findsOneWidget,
      );
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
      // The feed's own card, with its handle and its two actions.
      expect(find.text('cass'), findsOneWidget);
      expect(find.text('Like'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });
  });
}

/// A report we can inspect, so the page's tests never reach Firestore.
class _Reports implements Reports {
  _Reports({this.sends = true});

  final bool sends;
  final List<String> sent = [];
  final List<String> hidden = [];

  @override
  Future<bool> send({
    required ReportTarget type,
    required String targetKey,
    required String targetOwnerUid,
    required ReportReason reason,
  }) async {
    if (!sends) return false;
    sent.add('${type.wire}|$targetKey|$targetOwnerUid|${reason.wire}');
    return true;
  }

  @override
  Future<void> hide(ReportTarget type, String targetKey) async {
    if (type == ReportTarget.user) return;
    hidden.add(hiddenKey(type, targetKey));
  }
}
