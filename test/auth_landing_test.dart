import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/apple_sign_in_button.dart';
import 'package:sondr/features/auth/auth_landing.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/auth_screen.dart';
import 'package:sondr/features/auth/guest_prompts.dart';
import 'package:sondr/features/auth/handle_screen.dart';
import 'package:sondr/features/auth/invited_screen.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/links/invite_link.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/features/shell/main_shell.dart';

/// Where a finished sign-in leaves you.
///
/// Every door into the auth flow — Profile's account landing, the guest
/// prompt the Friends gate and the milestone and the first hour all
/// raise, Apple's button — ends on Home with the flow's screens gone,
/// including when the flow runs on through the handle and "Who invited
/// you?". A caller with a destination of its own gets its screen back
/// instead, and the tab it was on is left alone.
void main() {
  const me = 'uid_me';
  late FakeFirebaseFirestore db;
  late _Auth auth;
  late _Inviter inviter;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = _Auth();
    inviter = _Inviter();
  });

  /// The shell stands in for the app's: it says which tab it is on, so a
  /// landing can be read off the screen rather than out of a provider.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Widget Function(BuildContext context) onFirstRoute,
    int startTab = 2,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(ProfileRepository(db)),
          publishPublicProfileProvider.overrideWithValue(() async {}),
          pendingInviterProvider.overrideWithValue(inviter),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Consumer(
            builder: (context, ref, _) {
              // The tab the shell would be showing.
              final tab = ref.watch(selectedTabProvider);
              return Scaffold(
                body: Column(
                  children: [
                    Text('tab:$tab'),
                    Expanded(child: Builder(builder: onFirstRoute)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    // The shell starts where the person was: Profile, not Home, so a
    // landing on Home is a move and not a coincidence.
    final container = ProviderScope.containerOf(tester.element(find.text('tab:0')));
    container.read(selectedTabProvider.notifier).set(startTab);
    await tester.pumpAndSettle();
    expect(find.text('tab:$startTab'), findsOneWidget);
    return container;
  }

  /// A button that pushes [screen], as an entry point does.
  Widget door(BuildContext context, Widget screen, {String label = 'door'}) =>
      Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => screen),
          ),
          child: Text(label),
        ),
      );

  Future<void> signInByEmail(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'ada@example.com');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    // The screen's title says it too: the action is the last of the two.
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
  }

  Future<void> signUpByEmail(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'ada@example.com');
    await tester.enterText(find.byType(TextField).last, 'hunter22');
    await tester.tap(find.text('Create account').last);
    await tester.pumpAndSettle();
  }

  Future<void> claimHandle(WidgetTester tester, String handle) async {
    await tester.enterText(find.byType(TextField).first, handle);
    await tester.tap(find.text('Claim handle'));
    await tester.pumpAndSettle();
  }

  group('Profile\'s account flow', () {
    testWidgets('signing into an existing account lands on Home, the flow gone', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => door(c, const AuthScreen(startInSignUp: false)),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);

      await signInByEmail(tester);
      expect(auth.signedIn, 1);
      expect(find.byType(AuthScreen), findsNothing, reason: 'the flow is gone');
      expect(container.read(selectedTabProvider), kHomeTab, reason: 'Home');
      expect(find.text('tab:0'), findsOneWidget, reason: 'and the shell shows it');
    });

    testWidgets('creating an account runs on through the handle and the question, and ends on Home', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => door(c, const AuthScreen(startInSignUp: true)),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();

      await signUpByEmail(tester);
      expect(auth.signedUp, 1);
      // Straight to the handle, still not Home.
      expect(find.byType(HandleScreen), findsOneWidget);
      expect(container.read(selectedTabProvider), 2, reason: 'nothing has landed yet');

      await claimHandle(tester, 'ada');
      // Then the one question a new account is asked.
      expect(find.byType(InvitedScreen), findsOneWidget);
      expect(container.read(selectedTabProvider), 2, reason: 'still not landed');

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(InvitedScreen), findsNothing);
      expect(find.byType(HandleScreen), findsNothing);
      expect(container.read(selectedTabProvider), kHomeTab, reason: 'Home, at the end of the flow');
      expect(find.text('tab:0'), findsOneWidget);
      expect(inviter.cleared, 1);
    });
  });

  group('Apple', () {
    testWidgets('a returning account with a handle lands on Home', (tester) async {
      await db.doc('users/$me/meta/profile').set({'username': 'ada', 'displayName': 'Ada'});
      final container = await pump(
        tester,
        onFirstRoute: (c) => door(c, const Scaffold(body: Center(child: AppleSignInButton()))),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppleSignInButton));
      await tester.pumpAndSettle();

      expect(auth.appleSignIns, 1);
      expect(find.byType(AppleSignInButton), findsNothing, reason: 'the screen it sat on is gone');
      expect(container.read(selectedTabProvider), kHomeTab);
      expect(find.text('tab:0'), findsOneWidget);
    });

    testWidgets('a new account is sent to the handle, and that flow ends on Home', (tester) async {
      auth.appleDisplayName = 'Ada Lovelace';
      final container = await pump(
        tester,
        onFirstRoute: (c) => door(c, const Scaffold(body: Center(child: AppleSignInButton()))),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppleSignInButton));
      await tester.pumpAndSettle();

      expect(find.byType(HandleScreen), findsOneWidget);
      expect(container.read(selectedTabProvider), 2);
      await claimHandle(tester, 'ada');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(container.read(selectedTabProvider), kHomeTab);
      expect(find.text('tab:0'), findsOneWidget);
    });
  });

  group('the guest prompt — the Friends gate, the milestone, the first hour', () {
    testWidgets('Create account opens the flow, and finishing it lands on Home', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => Center(
          child: TextButton(
            onPressed: () => showCreateAccountPrompt(
              c,
              title: 'Create an account',
              message: 'Friends need an account.',
            ),
            child: const Text('door'),
          ),
        ),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      expect(find.text('Friends need an account.'), findsOneWidget);

      await tester.tap(find.text('Create account').last);
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);

      await signUpByEmail(tester);
      await claimHandle(tester, 'ada');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(container.read(selectedTabProvider), kHomeTab);
      expect(find.text('tab:0'), findsOneWidget);
      expect(find.byType(AuthScreen), findsNothing);
    });
  });

  group('a flow with a destination of its own', () {
    testWidgets('gets its screen back, and the tab it was on is left alone', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (flow) => Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('the flow'),
                        TextButton(
                          onPressed: () => Navigator.of(flow).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AuthScreen(
                                startInSignUp: false,
                                landing: AuthLanding.back,
                              ),
                            ),
                          ),
                          child: const Text('sign in to carry on'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('door'),
          ),
        ),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sign in to carry on'));
      await tester.pumpAndSettle();

      await signInByEmail(tester);
      expect(auth.signedIn, 1);
      expect(find.byType(AuthScreen), findsNothing, reason: 'the auth screen comes off');
      expect(find.text('the flow'), findsOneWidget, reason: 'and the flow is still there');
      expect(container.read(selectedTabProvider), 2, reason: 'not Home: the flow has its own end');
    });

    testWidgets('a sign-up with a destination of its own still returns there after the question', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (flow) => Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('the flow'),
                        TextButton(
                          onPressed: () => Navigator.of(flow).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AuthScreen(
                                startInSignUp: true,
                                landing: AuthLanding.back,
                              ),
                            ),
                          ),
                          child: const Text('create to carry on'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('door'),
          ),
        ),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('create to carry on'));
      await tester.pumpAndSettle();

      await signUpByEmail(tester);
      await claimHandle(tester, 'ada');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('the flow'), findsOneWidget);
      expect(container.read(selectedTabProvider), 2);
    });
  });

  group('naming yourself, signed in already', () {
    testWidgets('"Set your handle" and "Choose a handle" come back where they were', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => door(
          c,
          const HandleScreen(landing: AuthLanding.back),
          label: 'Set your handle',
        ),
      );
      await tester.tap(find.text('Set your handle'));
      await tester.pumpAndSettle();
      expect(find.byType(HandleScreen), findsOneWidget);

      await claimHandle(tester, 'ada');
      // No question: this account is not new.
      expect(find.byType(InvitedScreen), findsNothing);
      expect(find.byType(HandleScreen), findsNothing);
      expect(find.text('Set your handle'), findsOneWidget, reason: 'back where it was');
      expect(container.read(selectedTabProvider), 2, reason: 'the tab is not touched');
    });
  });

  group('the landing itself', () {
    testWidgets('home sets the tab before it pops, so no frame of the old tab is drawn', (tester) async {
      final container = await pump(
        tester,
        onFirstRoute: (c) => door(c, const AuthScreen(startInSignUp: false)),
      );
      await tester.tap(find.text('door'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'ada@example.com');
      await tester.enterText(find.byType(TextField).last, 'hunter22');
      await tester.tap(find.text('Sign in').last);
      // Frame by frame through the pop: the shell is never seen on the
      // tab that was showing.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(find.text('tab:2'), findsNothing, reason: 'frame $i');
      }
      await tester.pumpAndSettle();
      expect(container.read(selectedTabProvider), kHomeTab);
      expect(find.text('tab:0'), findsOneWidget);
    });
  });
}

/// The auth object, which every one of these flows goes through.
class _Auth implements AuthRepository {
  int signedIn = 0;
  int signedUp = 0;
  int appleSignIns = 0;
  String? appleDisplayName;

  @override
  User? get currentUser => null;

  @override
  bool get isAnonymous => true;

  @override
  Future<void> signInWithEmail(String email, String password) async => signedIn++;

  @override
  Future<void> signUpWithEmail(String email, String password) async => signedUp++;

  @override
  Future<AppleSignInResult> signInWithApple({
    Future<bool> Function()? confirmReplaceGuest,
  }) async {
    appleSignIns++;
    return AppleSignInResult(displayName: appleDisplayName);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Inviter implements PendingInviter {
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
