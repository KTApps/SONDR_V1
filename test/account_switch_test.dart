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
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/milestone_strip.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';

/// Signing out: no frame of the old account's Profile is drawn after it —
/// not its handle, not its figures — and the guest's Profile appears only
/// once its own (empty) data is in.
void main() {
  const handle = 'ada';

  Future<void> pump(WidgetTester tester, _Uid uid) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('No Firebase App')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _uidProvider.overrideWith(() => uid),
          currentUidProvider.overrideWith((ref) => ref.watch(_uidProvider)),
          authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
          authRepositoryProvider.overrideWithValue(_Auth()),
          // Each of the account's sources takes a moment, and answers for
          // whoever is signed in — ada's data for ada, nothing for a guest.
          tasksProvider.overrideWith(_SlowTasks.new),
          currentProfileProvider.overrideWith((ref) async {
            final u = ref.watch(currentUidProvider);
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return u == 'ada-uid' ? const Profile(uid: 'ada-uid', username: handle, displayName: 'Ada') : null;
          }),
          galleryPreviewProvider.overrideWith((ref) async => const []),
          collagesListProvider.overrideWith((ref) async => const []),
          milestoneStripProvider.overrideWith((ref) async => const []),
          friendshipsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: const ProfileScreen(),
            floatingActionButton: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => switchAccount(ref, () async {
                  await Future<void>.delayed(const Duration(milliseconds: 30));
                  ref.read(_uidProvider.notifier).set(null);
                }),
                child: const Text('sign out'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool showsAda(WidgetTester tester) =>
      find.text(handle).evaluate().isNotEmpty || find.textContaining('41').evaluate().isNotEmpty;

  testWidgets('after sign-out no frame shows the old account; the guest\'s page comes once its data is in', (tester) async {
    await pump(tester, _Uid('ada-uid'));
    expect(showsAda(tester), isTrue, reason: 'ada\'s page, to begin with');
    await tester.tap(find.text('sign out'));
    // Frame by frame through the change and the loading after it.
    var blankFrames = 0;
    var guestFrames = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      expect(showsAda(tester), isFalse, reason: 'frame $i still shows the old account');
      final blank = find.byType(ProfileScreen).evaluate().isNotEmpty && find.text('Milestones').evaluate().isEmpty;
      if (blank) blankFrames++;
      if (find.text('Milestones').evaluate().isNotEmpty) guestFrames++;
    }
    expect(blankFrames, greaterThan(0), reason: 'blank while the guest\'s data is on its way');
    expect(guestFrames, greaterThan(0), reason: 'and the guest\'s page once it is in');
    await tester.pumpAndSettle();
    expect(find.text('Milestones'), findsOneWidget);
    expect(showsAda(tester), isFalse);
  });

  testWidgets('falsified: without the gate the old account lingers while the guest\'s data loads', (tester) async {
    await pump(tester, _Uid('ada-uid'));
    final uid = tester.element(find.byType(ProfileScreen));
    ProviderScope.containerOf(uid).read(_uidProvider.notifier).set(null);
    await tester.pump(const Duration(milliseconds: 10));
    expect(showsAda(tester), isTrue, reason: 'the stale frame the gate exists to stop');
    await tester.pumpAndSettle();
  });
}

class _Uid extends Notifier<String?> {
  _Uid(this.initial);
  final String? initial;
  @override
  String? build() => initial;
  void set(String? uid) => state = uid;
}

final _uidProvider = NotifierProvider<_Uid, String?>(() => _Uid('ada-uid'));

class _SlowTasks extends TasksController {
  @override
  Future<List<Task>> build() async {
    final uid = ref.watch(currentUidProvider);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return uid == 'ada-uid'
        ? [Task(id: 'golf', name: 'Golf', secondsByDay: const {'2026-10-01': 41 * 3600})]
        : const [];
  }
}

class _Auth implements AuthRepository {
  @override
  User? get currentUser => null;
  @override
  bool get isAnonymous => true;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
