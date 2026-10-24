import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/handle_screen.dart';
import 'package:sondr/features/auth/invited_screen.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/links/invite_link.dart';
import 'package:sondr/features/links/invite_link_listener.dart';
import 'package:sondr/shared/sondr_field.dart';

import 'support/app_viewport.dart';

/// "Who invited you?" — asked once, of a new account, in the handle
/// screen's own layout.

const me = 'uid_me';
const them = 'uid_them';

class _Lookup implements HandleLookup {
  _Lookup(this.uids);

  final Map<String, String> uids;
  final List<String> asked = [];

  @override
  Future<String?> uidFor(String handle) async {
    asked.add(handle);
    return uids[handle];
  }
}

/// The real pruner reaches for shared_preferences, which has no platform
/// behind it in a test — and nothing here prunes anything.
class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Inviter implements PendingInviter {
  _Inviter([this.held]);

  String? held;
  int cleared = 0;

  @override
  Future<String?> read() async => held;

  @override
  Future<void> remember(String handle) async => held = handle;

  @override
  Future<void> clear() async {
    cleared++;
    held = null;
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late _Lookup lookup;
  late _Inviter inviter;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.doc('users/$me/meta/profile').set({
      'username': 'tanaka',
      'displayName': 'Tanaka',
    });
    await db.doc('usernames/tanaka').set({'uid': me});
    await db.doc('usernames/cass').set({'uid': them});
    lookup = _Lookup({'tanaka': me, 'cass': them});
    inviter = _Inviter();
  });

  Future<void> pump(WidgetTester tester, {double textScale = 1.0}) async {
    useReferenceViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          firebaseReadyProvider.overrideWithValue(true),
          friendsRepositoryProvider.overrideWithValue(
            FriendsRepository(db: db, uid: me, pruner: _NoPrune()),
          ),
          handleLookupProvider.overrideWithValue(lookup),
          pendingInviterProvider.overrideWithValue(inviter),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(kRefWidth, kRefHeight),
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(body: _Host()),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, String handle) async {
    await tester.enterText(find.byType(TextField), handle);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  group('the question', () {
    testWidgets('asks it, and offers a way past it', (tester) async {
      await pump(tester);
      expect(find.text('Who invited you?'), findsWidgets);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      // The field says whose handle it wants.
      expect(
        tester.widget<SondrField>(find.byType(SondrField)).label,
        'Their handle',
      );
    });

    testWidgets('prefilled from the link they followed', (tester) async {
      inviter = _Inviter('cass');
      await pump(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'cass',
      );
    });

    testWidgets('empty when they arrived on their own', (tester) async {
      await pump(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });
  });

  group('answering it', () {
    testWidgets('a handle writes the invite AND the request, together', (
      tester,
    ) async {
      await pump(tester);
      await answer(tester, 'cass');

      final invite = await db.doc('invites/$me').get();
      expect(invite.exists, isTrue);
      expect(invite.data()!['invitedBy'], them);
      expect(invite.data()!['invitedByHandle'], 'cass');
      expect(invite.data()!['at'], isNotNull);
      expect(invite.data()!.keys.toSet(),
          {'invitedBy', 'invitedByHandle', 'at'});

      final requests = await db.collection('friendships').get();
      expect(requests.docs.length, 1);
      expect(requests.docs.single.data()['status'], 'pending');
      expect(requests.docs.single.data()['requestedBy'], me);
      expect(requests.docs.single.data()['users'], containsAll([me, them]));

      // Asked and answered: the held handle is let go and the screen
      // leaves.
      expect(inviter.cleared, 1);
      expect(find.byType(InvitedScreen), findsNothing);
    });

    testWidgets('an uppercase answer is the same answer', (tester) async {
      await pump(tester);
      await answer(tester, 'CASS');
      expect((await db.doc('invites/$me').get()).data()!['invitedByHandle'],
          'cass');
    });

    testWidgets('a handle nobody holds says so, and writes nothing', (
      tester,
    ) async {
      await pump(tester);
      await answer(tester, 'ghost');
      expect(find.text(kHandleNotFound), findsOneWidget);
      expect((await db.doc('invites/$me').get()).exists, isFalse);
      expect((await db.collection('friendships').get()).docs, isEmpty);
      expect(find.byType(InvitedScreen), findsOneWidget);
    });

    testWidgets('their own handle says so, and writes nothing', (
      tester,
    ) async {
      await pump(tester);
      await answer(tester, 'tanaka');
      expect(find.text(kThatsYou), findsOneWidget);
      expect(kThatsYou, "That's you.");
      expect((await db.doc('invites/$me').get()).exists, isFalse);
    });

    testWidgets('something too short to be a handle is not looked up', (
      tester,
    ) async {
      await pump(tester);
      await answer(tester, 'ab');
      expect(find.text(kHandleNotFound), findsOneWidget);
      expect(lookup.asked, isEmpty);
    });

    testWidgets('already friends: the invite stands, no second request', (
      tester,
    ) async {
      await db.doc('friendships/${Friendship.pairId(me, them)}').set({
        'users': [me, them]..sort(),
        'requestedBy': them,
        'status': 'accepted',
      });
      await pump(tester);
      await answer(tester, 'cass');

      expect((await db.doc('invites/$me').get()).exists, isTrue);
      final all = await db.collection('friendships').get();
      expect(all.docs.length, 1);
      expect(all.docs.single.data()['status'], 'accepted',
          reason: 'the existing friendship was overwritten');
    });

    testWidgets('Skip writes nothing and leaves', (tester) async {
      inviter = _Inviter('cass');
      await pump(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect((await db.doc('invites/$me').get()).exists, isFalse);
      expect((await db.collection('friendships').get()).docs, isEmpty);
      expect(inviter.cleared, 1);
      expect(find.byType(InvitedScreen), findsNothing);
    });
  });

  group('the same screen as the one before it', () {
    /// It is the same moment in the same flow, so nothing may shift
    /// between the two: the prompt, the field, the primary action and the
    /// supporting one all land where the handle screen puts them.
    Future<Map<String, Rect>> layoutOf(
      WidgetTester tester, {
      required bool handleScreen,
      required double textScale,
    }) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            firebaseReadyProvider.overrideWithValue(true),
            friendsRepositoryProvider.overrideWithValue(
              FriendsRepository(db: db, uid: me, pruner: _NoPrune()),
            ),
            handleLookupProvider.overrideWithValue(lookup),
            pendingInviterProvider.overrideWithValue(inviter),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(kRefWidth, kRefHeight),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      // Pushed, so the handle screen shows its supporting
                      // action — the slot Skip stands in.
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => handleScreen
                              ? const HandleScreen()
                              : const InvitedScreen(),
                        ),
                      ),
                      child: const Text('go'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      return {
        'prompt': tester.getRect(
          find.textContaining(handleScreen ? 'This is how friends' : 'Who invited you?').last,
        ),
        'field': tester.getRect(find.byType(SondrField)),
        'primary': tester.getRect(
          find.text(handleScreen ? 'Claim handle' : 'Continue'),
        ),
        'supporting': tester.getRect(
          find.text(handleScreen ? 'Back' : 'Skip'),
        ),
      };
    }

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('element for element at $ts', (tester) async {
        final handle = await layoutOf(
          tester,
          handleScreen: true,
          textScale: ts,
        );
        final invited = await layoutOf(
          tester,
          handleScreen: false,
          textScale: ts,
        );

        for (final part in ['prompt', 'field', 'primary', 'supporting']) {
          expect(
            invited[part]!.top,
            closeTo(handle[part]!.top, 0.5),
            reason: '$part sits at a different height',
          );
        }
        // The prompt itself is one line where the handle screen's is two —
        // that is the sentence, not the layout, and the invisible copy of
        // the longer one is what keeps everything below it in place.
        for (final part in ['field', 'primary', 'supporting']) {
          expect(
            invited[part]!.height,
            closeTo(handle[part]!.height, 0.5),
            reason: '$part is a different height',
          );
        }
        // Which is worth stating directly: the gap from the question to
        // the field is the same on both.
        expect(
          invited['field']!.top - invited['prompt']!.top,
          closeTo(handle['field']!.top - handle['prompt']!.top, 0.5),
          reason: 'the space held for the prompt changed',
        );
        // The two actions are centred, as they are on the handle screen.
        for (final part in ['primary', 'supporting']) {
          expect(
            invited[part]!.center.dx,
            closeTo(kRefWidth / 2, 0.5),
            reason: part,
          );
        }
      });
    }
  });

  group('where it is asked', () {
    testWidgets('after a new account claims its handle', (tester) async {
      expect(const HandleScreen(afterSignUp: true).afterSignUp, isTrue);
      // And nowhere else: the Profile and friends-gate pushes take the
      // default.
      expect(const HandleScreen().afterSignUp, isFalse);
    });

    test('the two post-signup pushes are the only ones that ask', () {
      // The flag is what decides it, so the call sites are the contract.
      final asks = <String>[];
      for (final path in [
        'lib/features/auth/auth_screen.dart',
        'lib/features/auth/apple_sign_in_button.dart',
        'lib/features/auth/account_screen.dart',
        'lib/features/friends/friends_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        if (src.contains('afterSignUp: true')) asks.add(path);
      }
      expect(asks, [
        'lib/features/auth/auth_screen.dart',
        'lib/features/auth/apple_sign_in_button.dart',
      ]);
    });
  });
}

/// Pushes the screen the way the handle screen does, so there is something
/// to pop back to and the test can see it leave.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const InvitedScreen()),
      ),
      child: const Text('go'),
    ),
  );
}
