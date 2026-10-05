import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/friends_screen.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/profile/profile_screen.dart';

import 'support/app_viewport.dart';

/// Does the page fit the height a real device gives it?
///
/// Measured, never reasoned about. Both of these screens have overflowed
/// before — Profile by 42, and both times the arithmetic looked fine on
/// paper. A Flutter overflow surfaces as an exception during layout, so
/// [tester.takeException] is the whole assertion.

/// Asserts the page did not overflow, tolerating the unavoidable Firebase
/// "no app" error the account footer raises in a unit test.
///
/// Deliberately narrow: it drains every exception and fails on any overflow,
/// so a real layout break cannot hide behind the tolerated one.
void expectNoOverflow(WidgetTester tester) {
  final thrown = <Object>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    thrown.add(e);
  }
  expect(
    thrown.where((e) => e.toString().contains('overflowed')),
    isEmpty,
    reason: 'the page must fit the height the device gives it',
  );
  // Anything that is NOT the known Firebase absence is a real failure.
  expect(
    thrown.where((e) => !e.toString().contains('No Firebase App')),
    isEmpty,
  );
}

Profile _me() => const Profile(uid: 'me', username: 'me', displayName: 'Me');

Friendship _friend(int i) => Friendship.fromMap('me__u$i', {
      'users': ['me', 'u$i'],
      'requestedBy': 'me',
      'status': 'accepted',
      'profiles': {
        'me': {'username': 'me', 'displayName': 'Me'},
        'u$i': {'username': 'user$i', 'displayName': 'Friend Number $i'},
      },
    });

Block _block(int i) => Block(
      blocker: 'me',
      blocked: 'b$i',
      username: 'blocked$i',
      displayName: 'Blocked Person $i',
    );

/// A tab screen sits in the shell: the tab bar takes its own height plus the
/// bottom inset BEFORE the body is measured, and the Scaffold strips the
/// bottom padding so the screen's own SafeArea only removes the top.
/// Forgetting the tab bar is what made the last fit check read comfortable
/// while the page was overflowing by 42.
Widget _profileHarness({required int blocked}) => ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('me'),
        // The account footer reaches for FirebaseAuth.instance, which throws
        // with no Firebase in a test. Left alone it renders an ErrorWidget
        // that overflows by ~100,000px and drowns out the real answer.
        authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
        blockedAccountsProvider.overrideWith(
          (ref) => Stream.value([for (var i = 0; i < blocked; i++) _block(i)]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: const ProfileScreen(),
          bottomNavigationBar: const SizedBox(
            height: kTabBarHeight + kRefBottomInset,
          ),
        ),
      ),
    );

/// Friends is PUSHED from Profile on the root navigator, so it covers the tab
/// bar and gets the whole screen — a different budget from a tab screen.
Widget _friendsHarness({
  required int friends,
  required int blocked,
  int incoming = 0,
  int outgoing = 0,
}) =>
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('me'),
        currentProfileProvider.overrideWith((ref) async => _me()),
        friendsProvider.overrideWithValue(
          [for (var i = 0; i < friends; i++) _friend(i)],
        ),
        incomingRequestsProvider.overrideWithValue(
          [for (var i = 0; i < incoming; i++) _friend(100 + i)],
        ),
        outgoingRequestsProvider.overrideWithValue(
          [for (var i = 0; i < outgoing; i++) _friend(200 + i)],
        ),
        blockedAccountsProvider.overrideWith(
          (ref) => Stream.value([for (var i = 0; i < blocked; i++) _block(i)]),
        ),
      ],
      child: const MaterialApp(home: FriendsScreen()),
    );

void main() {
  group('Friends fits the reference device', () {
    testWidgets('with the Blocked link shown AND a full friends list',
        (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(_friendsHarness(friends: 30, blocked: 3));
      await tester.pumpAndSettle();

      expect(find.text('Blocked accounts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with every section open on top of it — the worst case',
        (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(_friendsHarness(
        friends: 30,
        blocked: 3,
        incoming: 4,
        outgoing: 4,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no blocks: the link is absent, and it still fits',
        (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(_friendsHarness(friends: 30, blocked: 0));
      await tester.pumpAndSettle();

      // Invisible in the common case — the whole point of the entry.
      expect(find.text('Blocked accounts'), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the white invite action stays the primary one',
        (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(_friendsHarness(friends: 5, blocked: 2));
      await tester.pumpAndSettle();

      // Order down the pinned group: Invite, then the two quiet ones.
      final invite = tester.getTopLeft(
        find.text('Invite your friends to Sondr'),
      );
      final blocked = tester.getTopLeft(find.text('Blocked accounts'));
      final back = tester.getTopLeft(find.text('Back'));
      expect(invite.dy, lessThan(blocked.dy));
      expect(blocked.dy, lessThan(back.dy));
    });
  });

  group('Profile fits the reference device', () {
    // The account footer builds FirebaseAuth.instance, which cannot exist in
    // a unit test, so that subtree is swapped for a box of a DELIBERATELY
    // generous height. If the page fits with an over-sized footer it fits
    // with the real one — the test can be optimistic about nothing.
    const generousFooter = 120.0;

    final realBuilder = ErrorWidget.builder;
    setUp(() {
      ErrorWidget.builder = (_) => const SizedBox(height: generousFooter);
    });
    tearDown(() => ErrorWidget.builder = realBuilder);

    testWidgets('with blocked accounts present — the entry has moved away',
        (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(_profileHarness(blocked: 2));
      await tester.pumpAndSettle();

      // This is what overflowed Profile by 42. It belongs to Friends now.
      expect(find.text('Blocked accounts'), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('with nothing blocked — identical, since nothing is '
        'conditional on blocks any more', (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(_profileHarness(blocked: 0));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
    });
  });
}
