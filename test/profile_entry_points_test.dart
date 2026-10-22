import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart';
import 'package:sondr/features/feed/widgets/feed_view.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/profile/other_profile_screen.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/features/shell/main_shell.dart';

/// Every way into another person's profile carries the one thing the page
/// needs: their uid. The denormalised handle on a post or a friendship is
/// what a row PRINTS; it is not an address.
const String me = 'me';
const String them = 'them';

Post _post() => MilestonePost(
  id: 'p1',
  authorUid: them,
  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
  createdAt: DateTime(2026, 10, 1),
  caption: null,
  taskName: 'Piano',
  milestoneHours: 20,
  totalHours: 20,
);

Comment _comment() => Comment(
  id: 'c1',
  authorUid: them,
  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
  text: 'well done',
  createdAt: DateTime(2026, 10, 1),
);

/// The whole scope, built inline: `Override` is not a nameable type in a
/// test, so the overrides cannot be handed about in a list.
Widget _app({
  required Widget home,
  String uid = me,
  List<Comment>? comments,
  List<String> friendUids = const [],
}) => ProviderScope(
  overrides: [
    currentUidProvider.overrideWithValue(uid),
    friendshipsProvider.overrideWith(
      (ref) => Stream.value(const <Friendship>[]),
    ),
    blockedAccountsProvider.overrideWith(
      (ref) => Stream.value(const <Block>[]),
    ),
    publicProfileProvider.overrideWith(
      (ref, ofUid) async => PublicProfile(
        uid: ofUid,
        handle: 'cass',
        displayName: 'Cass',
        hours: 7,
      ),
    ),
    profilePostsProvider.overrideWith((ref, ofUid) async => const <Post>[]),
    friendUidsProvider.overrideWith((ref, ofUid) async => friendUids),
    if (comments != null)
      postCommentsProvider.overrideWith(
        (ref, postId) => AsyncValue.data(comments),
      ),
  ],
  child: MaterialApp(theme: AppTheme.dark(), home: home),
);

void main() {
  testWidgets('a post byline opens its author', (tester) async {
    await tester.pumpWidget(
      _app(home: Scaffold(body: FeedView(posts: [_post()]))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OtherProfileScreen), findsNothing);

    await tester.tap(find.text('Cass'));
    await tester.pumpAndSettle();
    final screen = tester.widget<OtherProfileScreen>(
      find.byType(OtherProfileScreen),
    );
    expect(screen.uid, them);
    // And what the byline already knew, so the page is never nameless.
    expect(screen.handle, 'cass');
    expect(screen.displayName, 'Cass');
  });

  testWidgets('my own byline goes to my Profile tab, not a second copy', (
    tester,
  ) async {
    late int tab;
    await tester.pumpWidget(
      _app(
        uid: them,
        home: Consumer(
          builder: (context, ref, _) {
            tab = ref.watch(selectedTabProvider);
            return Scaffold(body: FeedView(posts: [_post()]));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tab, 0);

    await tester.tap(find.text('Cass'));
    await tester.pumpAndSettle();
    expect(find.byType(OtherProfileScreen), findsNothing);
    expect(tab, kProfileTabIndex);
  });

  testWidgets('a comment author opens their profile', (tester) async {
    await tester.pumpWidget(
      _app(
        comments: [_comment()],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCommentsSheet(context, 'p1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('well done'), findsOneWidget);

    await tester.tap(find.text('Cass'));
    await tester.pumpAndSettle();
    final screen = tester.widget<OtherProfileScreen>(
      find.byType(OtherProfileScreen),
    );
    expect(screen.uid, them);
    expect(screen.handle, 'cass');
  });

  testWidgets('a search result carries the uid, not just the handle', (
    tester,
  ) async {
    // The filter the search runs is where the uid used to be thrown away.
    final matches = handlesNotBlocked(
      const [MapEntry('cass', them), MapEntry('ada', 'other')],
      const {},
    );
    expect(matches.map((m) => m.handle), ['cass', 'ada']);
    expect(matches.first.uid, them);

    // And a row built from one opens that person.
    await tester.pumpWidget(
      _app(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => openProfile(context, ref, matches.first.uid),
                child: const Text('cass'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('cass'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OtherProfileScreen>(find.byType(OtherProfileScreen)).uid,
      them,
    );
  });

  testWidgets('a friendship row opens the other participant', (tester) async {
    final f = Friendship(
      id: Friendship.pairId(me, them),
      users: [me, them]..sort(),
      requestedBy: me,
      status: FriendshipStatus.accepted,
      profiles: const {
        them: FriendIdentity(username: 'cass', displayName: 'Cass'),
      },
    );
    await tester.pumpWidget(
      _app(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => openProfile(context, ref, f.otherUid(me)),
                child: const Text('cass'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('cass'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OtherProfileScreen>(find.byType(OtherProfileScreen)).uid,
      them,
    );
  });

  testWidgets('their friends list opens each person it lists', (tester) async {
    await tester.pumpWidget(
      _app(
        friendUids: const [them],
        home: const FriendsOfScreen(uid: 'someone', handle: 'ada'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('cass'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OtherProfileScreen>(find.byType(OtherProfileScreen)).uid,
      them,
    );
  });
}
