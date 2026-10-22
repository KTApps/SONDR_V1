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

/// Accepting says itself: the row leaves Requests and joins Friends, and
/// the profile's status line reads Friends. A sentence announcing it was a
/// third telling.
void main() {
  testWidgets('accepting a request announces nothing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
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
  });
}
