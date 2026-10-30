import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/account_switch.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/notifications/notifications_repository.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/milestone_strip.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/shared/blur_sheet.dart';

/// Sign-out, frame by frame, as the phone has it: the More sheet open
/// over the Profile, Sign out tapped, the auth call resolving BEFORE the
/// auth stream says so, every source a step away from the uid — and not
/// one frame of the old account's Profile, nor a populated Profile of any
/// kind, before the guest's own empty one.
void main() {
  const handle = 'ada';

  /// A source as the app has them: a repository that follows the uid,
  /// and data fetched through it, a moment later.
  final repoProvider = Provider<String?>((ref) => ref.watch(currentUidProvider));

  Future<_Uid> pump(WidgetTester tester, {required bool gated}) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('No Firebase App')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final uid = _Uid('ada-uid');
    final auth = _Auth('ada-uid');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _uidProvider.overrideWith(() => uid),
          currentUidProvider.overrideWith((ref) => ref.watch(_uidProvider)),
          authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
          authRepositoryProvider.overrideWithValue(auth),
          tasksProvider.overrideWith(() => _SlowTasks(repoProvider)),
          // Nobody signed in: every source answers at once, as the app's
          // do (no repository, nothing to fetch). An account: a moment.
          currentProfileProvider.overrideWith((ref) async {
            final u = ref.watch(repoProvider);
            if (u == null) return null;
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return u == 'ada-uid' ? const Profile(uid: 'ada-uid', username: handle, displayName: 'Ada') : null;
          }),
          galleryPreviewProvider.overrideWith((ref) async {
            if (ref.watch(repoProvider) == null) return const [];
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return const [];
          }),
          collagesListProvider.overrideWith((ref) async => const []),
          milestoneStripProvider.overrideWith((ref) async => const []),
          friendshipsProvider.overrideWith((ref) => Stream.value(const [])),
          feedProvider.overrideWithValue(const AsyncValue.data([])),
          myNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: const ProfileScreen(),
            floatingActionButton: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showBlurSheet(
                  context,
                  (sheet) => BlurView(
                    items: [
                      BlurItem(
                        label: 'Sign out',
                        onTap: () async {
                          Future<void> signOut() async {
                            // As the app's signOut() does: sign out, then a
                            // fresh guest. The auth object moves at once;
                            // the stream says so in two events, a moment
                            // later each — null, then the new guest.
                            await Future<void>.delayed(const Duration(milliseconds: 20));
                            auth.user = 'guest-anon';
                            unawaited(Future<void>.delayed(const Duration(milliseconds: 30), () => uid.set(null)));
                            unawaited(Future<void>.delayed(const Duration(milliseconds: 60), () => uid.set('guest-anon')));
                          }
                          if (gated) {
                            await switchAccount(ref, signOut, endsAs: () => auth.currentUser?.uid);
                          } else {
                            await signOut();
                          }
                          sheet.close();
                        },
                      ),
                    ],
                  ),
                ),
                child: const Text('open-sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return uid;
  }

  bool oldAccount(WidgetTester tester) =>
      find.text(handle).evaluate().isNotEmpty || find.textContaining('41').evaluate().isNotEmpty;
  bool populated(WidgetTester tester) =>
      find.text('Golf').evaluate().isNotEmpty || find.text('Spanish').evaluate().isNotEmpty;
  bool guestProfile(WidgetTester tester) =>
      find.text('Milestones').evaluate().isNotEmpty && !populated(tester);
  bool blurUp(WidgetTester tester) => find.byType(BlurSheet).evaluate().isNotEmpty;

  /// What each frame shows, for the report.
  String frame(WidgetTester tester) {
    final parts = <String>[
      if (blurUp(tester)) 'blur',
      if (oldAccount(tester)) 'OLD',
      if (populated(tester)) 'populated',
      if (guestProfile(tester)) 'guest',
      if (!blurUp(tester) && !populated(tester) && !guestProfile(tester) && find.byType(ProfileScreen).evaluate().isNotEmpty) 'blank',
    ];
    return parts.isEmpty ? '-' : parts.join('+');
  }

  Future<List<String>> signOutFrames(WidgetTester tester, {required bool gated}) async {
    await pump(tester, gated: gated);
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
    expect(oldAccount(tester), isTrue, reason: 'ada\'s Profile under the sheet, to begin with');
    await tester.tap(find.text('Sign out'));
    final frames = <String>[];
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      frames.add(frame(tester));
    }
    await tester.pumpAndSettle();
    frames.add(frame(tester));
    return frames;
  }

  testWidgets('tap → the blur stays over nothing of any account → the guest Profile, directly', (tester) async {
    final frames = await signOutFrames(tester, gated: true);
    // ignore: avoid_print
    print('FRAMES gated: ${frames.join(' ')}');
    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].contains('OLD'), isFalse, reason: 'frame $i shows the old account: ${frames[i]}');
      expect(frames[i].contains('populated'), isFalse, reason: 'frame $i shows a populated Profile: ${frames[i]}');
    }
    final firstGuest = frames.indexWhere((f) => f.contains('guest'));
    expect(firstGuest, greaterThan(0), reason: 'the guest Profile arrives');
    // The blur holds until the guest state is ready: no frame without the
    // blur before the guest's own Profile.
    for (var i = 1; i < firstGuest; i++) {
      expect(frames[i].contains('blur'), isTrue, reason: 'frame $i let the blur go early: ${frames[i]}');
    }
    expect(frames.last, 'guest');
  });

  testWidgets('falsified: without the switch a populated Profile — the local seed, then the old account — shows', (tester) async {
    final frames = await signOutFrames(tester, gated: false);
    // ignore: avoid_print
    print('FRAMES ungated: ${frames.join(' ')}');
    expect(frames.any((f) => f.contains('populated')), isTrue,
        reason: 'the populated frame the switch exists to stop');
  });
}

class _Uid extends Notifier<String?> {
  _Uid(this.initial);
  final String? initial;
  @override
  String? build() => initial;
  void set(String? uid) => state = uid;
}

final _uidProvider = NotifierProvider<_Uid, String?>(() => _Uid(null));

class _SlowTasks extends TasksController {
  _SlowTasks(this.repo);
  final Provider<String?> repo;
  @override
  Future<List<Task>> build() async {
    final uid = ref.watch(repo);
    // Nobody signed in: the local repository, which answers at once —
    // with its seed. An account: the server, a moment later.
    if (uid == null) return [Task(id: 'seed', name: 'Spanish', secondsByDay: const {'2026-10-01': 13 * 3600})];
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return uid == 'ada-uid'
        ? [Task(id: 'golf', name: 'Golf', secondsByDay: const {'2026-10-01': 41 * 3600})]
        : const [];
  }
}

/// The auth object: synchronous, and ahead of its own stream.
class _Auth implements AuthRepository {
  _Auth(this.user);
  String? user;
  @override
  User? get currentUser => user == null ? null : _FakeUser(user!);
  @override
  bool get isAnonymous => true;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  bool get isAnonymous => true;
  @override
  String? get email => null;
  @override
  String? get displayName => null;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
