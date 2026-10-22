import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/block.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/models/collage.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/milestone_strip.dart';
import 'package:sondr/features/profile/other_profile_screen.dart';
import 'package:sondr/features/profile/profile_metrics.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/sondr_action.dart';

import 'support/app_viewport.dart';
import 'tiny_png.dart';

/// Their profile is the personal Profile's composition about somebody else,
/// so it is held to the personal Profile's measurements: the same hero, the
/// same section rhythm, and a first screen that ends on the same line.
const String me = 'me';
const String them = 'them';

/// The 13 Pro the page is composed on.
const double w13 = 390;
const double h13 = 844;
const double top13 = 47;

/// The bottom of the SafeArea — past this is below the fold.
const double fold13 = h13 - kRefBottomInset;

Task _task(String name, {int seconds = 45900}) =>
    Task(id: name, name: name, secondsByDay: {'2026-10-01': seconds});

Photo _photo(int i) => Photo(
  taskId: 't',
  taskName: 'Task 0',
  dayKey: '2026-10-01',
  timestamp: 1000 + i,
  sessionSeconds: 60,
  photoUrl: 'https://x/$i.jpg',
  storagePath: 'p',
);

Friendship _friendship({bool accepted = true}) => Friendship(
  id: Friendship.pairId(me, them),
  users: [me, them]..sort(),
  requestedBy: me,
  status: accepted ? FriendshipStatus.accepted : FriendshipStatus.pending,
  profiles: const {
    them: FriendIdentity(username: 'cass', displayName: 'Cass'),
  },
);

Post _milestone(int i, {bool photo = true}) => MilestonePost(
  id: 'm$i',
  authorUid: them,
  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
  createdAt: DateTime(2026, 10, i + 1),
  caption: null,
  photos: photo
      ? [PostPhoto(url: 'https://x/m$i.jpg', storagePath: 'p')]
      : const [],
  taskName: 'Piano',
  milestoneHours: 20,
  totalHours: 20,
);

Post _session(int i, {bool photo = true}) => SessionPost(
  id: 's$i',
  authorUid: them,
  author: const PostAuthor(username: 'cass', displayName: 'Cass'),
  createdAt: DateTime(2026, 9, i + 1),
  caption: null,
  photos: photo
      ? [PostPhoto(url: 'https://x/s$i.jpg', storagePath: 'p')]
      : const [],
  taskName: 'Piano',
  sessionSeconds: 3600,
);

class _FakeTasks implements TasksRepository {
  _FakeTasks(this.tasks);
  final List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<void> delete(String taskId) async {}
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
  @override
  Future<void> save(Task task) async {}
}

void _asThirteenPro(WidgetTester tester) {
  tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(
    top: top13 * 3,
    bottom: kRefBottomInset * 3,
  );
  addTearDown(tester.view.reset);
}

void _ignoreFirebaseAbsence() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('No Firebase App')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void expectNoOverflow(WidgetTester tester) {
  final thrown = <Object>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    thrown.add(e);
  }
  expect(thrown.where((e) => e.toString().contains('overflowed')), isEmpty);
}

void main() {
  group('page titles', () {
    testWidgets('their posts grid names nothing, and nothing moves', (
      tester,
    ) async {
      _asThirteenPro(tester);
      final before = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = before);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(me),
            profilePostsProvider.overrideWith(
              (ref, uid) async => [_milestone(0)],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const PostsGridScreen(
              uid: them,
              handle: 'cass',
              title: 'Posts',
              milestonesOnly: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('cass’s posts'), findsNothing);
      // Measured with the title still there, on a 13 Pro.
      expect(tester.getRect(find.byType(GridView)).top, closeTo(118.55, 0.5));
    });
  });


  Future<void> pumpTheirs(
    WidgetTester tester, {
    bool friends = true,
    List<Post> posts = const [],
    List<String> friendUids = const ['a', 'b'],
    double textScale = 1.0,
    PublicProfile? published = const PublicProfile(
      uid: them,
      handle: 'cass',
      displayName: 'Cass',
      hours: 41,
    ),
  }) async {
    // Unmount anything a previous pump left behind: a ProviderScope
    // cannot change how many overrides it has.
    await tester.pumpWidget(const SizedBox.shrink());
    _asThirteenPro(tester);
    final before = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = before);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          friendshipsProvider.overrideWith(
            (ref) => Stream.value(friends ? [_friendship()] : const []),
          ),
          blockedAccountsProvider.overrideWith(
            (ref) => Stream.value(const <Block>[]),
          ),
          publicProfileProvider.overrideWith((ref, uid) async => published),
          profilePostsProvider.overrideWith((ref, uid) async => posts),
          friendUidsProvider.overrideWith((ref, uid) async => friendUids),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const OtherProfileScreen(uid: them),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The personal Profile, pinned: one task and a strip, in the shell.
  Future<void> pumpMine(WidgetTester tester) async {
    // Unmount anything a previous pump left behind: a ProviderScope
    // cannot change how many overrides it has.
    await tester.pumpWidget(const SizedBox.shrink());
    _asThirteenPro(tester);
    _ignoreFirebaseAbsence();
    final before = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = before);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          tasksRepositoryProvider.overrideWithValue(_FakeTasks([_task('Task 0')])),
          currentProfileProvider.overrideWith(
            (ref) async =>
                const Profile(uid: me, username: 'tanaka', displayName: 'T'),
          ),
          galleryPreviewProvider.overrideWith((ref) async => const <Photo>[]),
          collagesListProvider.overrideWith((ref) async => const <Collage>[]),
          milestoneStripProvider.overrideWith(
            (ref) async => [
              for (var i = 0; i < 2; i++)
                MilestoneStripEntry(
                  task: _task('Task 0'),
                  bandHours: 20,
                  photo: _photo(i),
                  crossedAt: 1000 + i,
                  detail: const BandDetail(collage: null, photos: []),
                ),
            ],
          ),
          friendshipsProvider.overrideWith(
            (ref) => Stream.value(const <Friendship>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: const ProfileScreen(),
            bottomNavigationBar: const SizedBox(
              height: kTabBarHeight + kRefBottomInset,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the first screen', () {
    testWidgets('ends on the line the personal Profile ends on', (
      tester,
    ) async {
      await pumpMine(tester);
      // The personal Profile's last element: the ring label, pinned to
      // Home's "View your progress" line.
      final mine = tester.getRect(find.text('Task 0')).bottom;

      await pumpTheirs(
        tester,
        posts: [_milestone(0), _milestone(1), _session(0)],
      );
      final theirs = tester.getRect(find.byType(ProfileStripTile).last).bottom;
      expect(theirs, closeTo(mine, 0.5));
    });

    testWidgets('all three sections are visible before the fold', (
      tester,
    ) async {
      await pumpTheirs(
        tester,
        posts: [_milestone(0), _milestone(1), _session(0)],
      );
      for (final label in ['Friends', 'Milestones', 'Posts']) {
        final heading = find.widgetWithText(ProfileHeading, label);
        expect(heading, findsOneWidget, reason: label);
        expect(
          tester.getRect(heading).bottom,
          lessThan(fold13),
          reason: '$label is past the fold',
        );
      }
      // And the strips they introduce.
      expect(
        tester.getRect(find.byType(ProfileStripTile).last).bottom,
        lessThan(fold13),
      );
      expectNoOverflow(tester);
    });

    testWidgets('Remove friend, Block and Back are below it', (tester) async {
      await pumpTheirs(tester, posts: [_milestone(0)]);
      for (final label in ['Remove friend', 'Block', 'Back']) {
        final action = find.widgetWithText(SondrAction, label);
        expect(action, findsOneWidget, reason: label);
        expect(
          tester.getRect(action).top,
          greaterThanOrEqualTo(fold13),
          reason: '$label is above the fold',
        );
      }
    });

    testWidgets('the status sits in the subtitle\'s slot, at its size', (
      tester,
    ) async {
      await pumpTheirs(tester, posts: [_milestone(0)]);
      final scale = figmaScale(
        tester.element(find.byType(OtherProfileScreen)),
      );
      final handle = tester.getRect(find.text('cass'));
      final status = tester.getRect(find.text('Friends').first);
      expect(
        status.top - handle.bottom,
        closeTo(kProfileHandleToSubline * scale, 0.5),
      );
      final text = tester.widget<Text>(find.text('Friends').first);
      expect(text.style?.fontSize, closeTo(13 * scale, 0.01));
      // A state, not an offer: grey, and nothing happens when it is tapped.
      expect(text.style?.color, const Color(0xFF6E6E6E));
    });

    testWidgets('an offer is white and tappable, a state is not', (
      tester,
    ) async {
      await pumpTheirs(tester, friends: false);
      final add = tester.widget<Text>(find.text('Add friend'));
      expect(add.style?.fontSize, isNotNull);
      expect(add.style?.color, const Color(0xFFFAFAFA));
      expect(
        find.ancestor(
          of: find.text('Add friend'),
          matching: find.byType(GestureDetector),
        ),
        findsWidgets,
      );
    });

    testWidgets('a stranger gets a compact page, top-anchored', (
      tester,
    ) async {
      await pumpTheirs(tester, friends: false);
      final scale = figmaScale(
        tester.element(find.byType(OtherProfileScreen)),
      );
      // Nothing of theirs, so nothing to reach for: no sections, and the
      // hero at its fixed gap rather than stretched toward a line that
      // has nothing to land on it.
      expect(find.byType(ProfileHeading), findsNothing);
      final handle = tester.getRect(find.text('cass'));
      final status = tester.getRect(find.text('Add friend'));
      final emblem = tester.getRect(find.byType(ProgressRing));
      expect(
        handle.top - emblem.bottom,
        closeTo(kProfileHeroGap * scale, 0.5),
        reason: 'the hero is fixed, not stretched',
      );
      // The invitation, and then nothing until the fold: the slack is at
      // the foot, not spread through the page.
      expect(
        find.text('Add each other as friends to see posts and milestones.'),
        findsOneWidget,
      );
      expect(status.bottom, lessThan(fold13 / 2));
    });
  });

  group('whatever the text size', () {
    for (final ts in [0.824, 1.0, 1.235]) {
      for (final (name, friends, posts) in [
        ('a friend with posts', true, [0, 1, 2]),
        ('a friend with nothing to show', true, <int>[]),
        ('a stranger', false, <int>[]),
      ]) {
        testWidgets('$name at textScale $ts', (tester) async {
          await pumpTheirs(
            tester,
            friends: friends,
            textScale: ts,
            posts: [
              for (final i in posts)
                if (i.isEven) _milestone(i) else _session(i),
            ],
          );
          expectNoOverflow(tester);
          final scale = figmaScale(
            tester.element(find.byType(OtherProfileScreen)),
          );

          // THE VOID GUARD: every gap the page actually renders, on this
          // data, at this text size.
          final ordered = <(String, Rect)>[
            ('handle', tester.getRect(find.text('cass'))),
            (
              'status',
              tester.getRect(
                find.text(friends ? 'Friends' : 'Add friend').first,
              ),
            ),
            // The stats block as one element — the figure and its label
            // are a unit, and the gap being guarded is the hero's.
            ('stats', tester.getRect(find.byType(ProfileStat).first)),
          ];
          for (var i = 0; i < ordered.length - 1; i++) {
            final gap = ordered[i + 1].$2.top - ordered[i].$2.bottom;
            expect(
              gap,
              greaterThan(-0.01),
              reason: '"${ordered[i].$1}" overlaps "${ordered[i + 1].$1}" '
                  '($name, $ts)',
            );
            expect(
              gap,
              lessThanOrEqualTo(kProfileHeroGapMax * scale + 0.01),
              reason: 'a void of $gap after "${ordered[i].$1}" ($name, $ts)',
            );
          }
        });
      }
    }
  });
}
