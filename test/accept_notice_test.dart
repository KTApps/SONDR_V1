import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/friends/friends_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:sondr/features/friends/content_prune.dart';

/// Accepting says itself: the row leaves Requests and joins Friends, and
/// the profile's status line reads Friends. A sentence announcing it was a
/// third telling.
/// Prunes nothing; the accept is what this is about.
class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

void main() {
  testWidgets('accepting a request announces nothing', (tester) async {
    // iOS, as the app is. Tests default to Android, where a focused empty
    // field draws a draggable selection handle just below the caret —
    // right over the Requests header, which then swallows the tap. The
    // field opens focused now, so this matters.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // A real repository over a fake Firestore, so Accept actually runs:
    // with a null repository the tap never reaches the accept at all, and
    // the test would pass with the notice still there.
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('me').collection('meta').doc('profile')
        .set({'username': 'ada', 'displayName': 'Ada'});
    await db.collection('friendships').doc(Friendship.pairId('me', 'them')).set({
      'users': ['me', 'them'],
      'requestedBy': 'them',
      'status': 'pending',
      'profiles': {
        'them': {'username': 'cass', 'displayName': 'Cass'},
      },
    });
    final repo = FriendsRepository(db: db, uid: 'me', pruner: _NoPrune());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          friendsRepositoryProvider.overrideWithValue(repo),
          currentProfileProvider.overrideWith(
            (ref) async =>
                const Profile(uid: 'me', username: 'ada', displayName: 'Ada'),
          ),
          blockedAccountsProvider.overrideWith(
            (ref) => Stream.value(const <Block>[]),
          ),
          friendshipsProvider.overrideWith(
            (ref) => Stream.value([
              Friendship(
                id: Friendship.pairId('me', 'them'),
                users: const ['me', 'them'],
                requestedBy: 'them',
                status: FriendshipStatus.pending,
                profiles: const {
                  'them': FriendIdentity(username: 'cass', displayName: 'Cass'),
                },
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const FriendsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Requests and accept.
    await tester.tap(find.text('1 Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.textContaining('now friends'), findsNothing);
    // It really accepted.
    final doc = await db
        .collection('friendships')
        .doc(Friendship.pairId('me', 'them'))
        .get();
    expect(doc.data()?['status'], 'accepted');
    // Restored inside the body: the framework checks before teardown runs.
    debugDefaultTargetPlatformOverride = null;
  });
}
