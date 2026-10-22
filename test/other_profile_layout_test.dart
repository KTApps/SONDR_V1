import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/spacing.dart';
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
import 'package:sondr/features/profile/profile_action_bar.dart';
import 'package:sondr/features/profile/profile_metrics.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/features/shell/main_shell.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/ring/progress_ring.dart';

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
    List<Block> blocks = const [],
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
          blockedAccountsProvider.overrideWith((ref) => Stream.value(blocks)),
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
  Future<void> pumpMine(WidgetTester tester, {double textScale = 1.0}) async {
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
      // Within a point: the strip tile is that much taller than the ring
      // row it stands in for, and that point is taken from the clearance
      // below rather than from anything above.
      final theirs = tester.getRect(find.byType(ProfileStripTile).last).bottom;
      expect(theirs, closeTo(mine, 1.2));
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

    testWidgets('the actions stand on the tab bar\'s own three slots', (
      tester,
    ) async {
      // The real bar, measured, then the profile's.
      tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(
        top: top13 * 3,
        bottom: kRefBottomInset * 3,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: TextTabBar(currentIndex: 2, onSelect: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tabBar = tester.getRect(find.byType(TextTabBar));
      final tabs = {
        for (final label in ['Home', 'Feed', 'Profile'])
          label: tester.getRect(find.text(label)).center,
      };

      await pumpTheirs(tester, posts: [_milestone(0)]);
      final bar = tester.getRect(find.byType(ProfileActionBar));
      expect(bar.top, closeTo(tabBar.top, 0.5));
      expect(bar.bottom, closeTo(tabBar.bottom, 0.5));
      expect(bar.height, closeTo(tabBar.height, 0.5));

      for (final (label, tab) in [
        ('Remove', 'Home'),
        ('Back', 'Feed'),
        ('Block', 'Profile'),
      ]) {
        final slot = tester.getRect(find.text(label)).center;
        expect(slot.dx, closeTo(tabs[tab]!.dx, 0.5), reason: '$label x');
        expect(slot.dy, closeTo(tabs[tab]!.dy, 0.5), reason: '$label y');
        final style = tester.widget<Text>(find.text(label)).style;
        expect(style?.fontSize, ProfileActionBar.labelSize);
        expect(style?.fontWeight, FontWeight.w500);
        expect(style?.color, const Color(0xFF6E6E6E));
      }
      // Nothing here is selected, so nothing is underlined.
      expect(
        find.descendant(
          of: find.byType(ProfileActionBar),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration != null,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('Back is always the middle slot, whatever the state', (
      tester,
    ) async {
      Offset backCentre() => tester.getRect(find.text('Back')).center;

      await pumpTheirs(tester, posts: [_milestone(0)]);
      final centre = backCentre();
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);

      // A stranger: no Remove, Block still on the right, Back unmoved.
      await pumpTheirs(tester, friends: false);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Block'), findsOneWidget);
      expect(backCentre(), centre);

      // Someone I blocked: neither, and Unblock is in the status line.
      await pumpTheirs(
        tester,
        friends: false,
        blocks: const [
          Block(blocker: me, blocked: them, username: 'cass', displayName: 'Cass'),
        ],
      );
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Block'), findsNothing);
      expect(find.text('Unblock'), findsOneWidget);
      expect(backCentre(), centre);
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

  group('the Posts grid', () {
    testWidgets('four across, filling the gutter exactly', (tester) async {
      await pumpTheirs(
        tester,
        posts: [
          _milestone(0),
          _milestone(1),
          for (var i = 2; i < 6; i++) _session(i),
        ],
      );
      final scale = figmaScale(
        tester.element(find.byType(OtherProfileScreen)),
      );
      // Two tiles in the Milestones strip, then the grid's six: one row
      // of four and one of two.
      final tiles = find.byType(ProfileStripTile);
      expect(tiles, findsNWidgets(8));
      final r0 = [for (var i = 2; i < 6; i++) tester.getRect(tiles.at(i))];
      final r1 = [for (var i = 6; i < 8; i++) tester.getRect(tiles.at(i))];

      // The row starts on the gutter and ends on it — no bleed.
      final width = tester.getSize(find.byType(OtherProfileScreen)).width;
      expect(r0.first.left, closeTo(kProfileGutter * scale, 0.5));
      expect(r0.last.right, closeTo(width - kProfileGutter * scale, 0.5));
      // Four square tiles, three gaps of 8.
      for (final t in r0) {
        expect(t.width, closeTo(t.height, 0.01));
        expect(t.width, closeTo(r0.first.width, 0.01));
      }
      for (var i = 1; i < 4; i++) {
        expect(
          r0[i].left - r0[i - 1].right,
          closeTo(kProfileStripGap * scale, 0.5),
          reason: 'gap $i',
        );
      }
      // The second row follows at the same gap, and a short row is not
      // stretched to fill.
      expect(r1.first.top - r0.first.bottom, closeTo(kProfileStripGap * scale, 0.5));
      expect(r1.first.left, closeTo(r0.first.left, 0.5));
      expect(r1.last.right, lessThan(r0.last.right));
    });

    testWidgets('the heading and the first row have not moved', (
      tester,
    ) async {
      // The build-62 positions, with the strip where the grid now is.
      await pumpTheirs(
        tester,
        posts: [
          _milestone(0),
          _milestone(1),
          for (var i = 2; i < 9; i++) _session(i),
        ],
      );
      expect(
        tester.getRect(find.text('Posts')).top,
        closeTo(619.64, 0.5),
      );
      // The grid's first row, which is the third tile on the page: the
      // Milestones strip holds the first two.
      expect(
        tester.getRect(find.byType(ProfileStripTile).at(2)).top,
        closeTo(663.45, 0.5),
      );
    });

    testWidgets('the Milestones strip is still a sideways scroller', (
      tester,
    ) async {
      await pumpTheirs(
        tester,
        posts: [_milestone(0), _milestone(1), _session(0)],
      );
      final scrollers = find.descendant(
        of: find.byType(OtherProfileScreen),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      // Exactly one: Milestones. Posts is a grid now.
      expect(scrollers, findsOneWidget);
      // And it is full-bleed: its own padding is the gutter.
      final strip = tester.widget<SingleChildScrollView>(scrollers);
      expect(strip.padding, isNotNull);
      expect(tester.getRect(scrollers).left, 0);
    });

    testWidgets('the last row ends above the bar where my own content does', (
      tester,
    ) async {
      await pumpTheirs(
        tester,
        posts: [
          _milestone(0),
          _milestone(1),
          for (var i = 2; i < 12; i++) _session(i),
        ],
      );
      final scale = figmaScale(
        tester.element(find.byType(OtherProfileScreen)),
      );
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(ProfileActionBar));
      final lastTile = tester.getRect(find.byType(ProfileStripTile).last);
      // kSpacingBase, the same trailing space the personal Profile leaves
      // under its account block at its own scroll end.
      expect(bar.top - lastTile.bottom, closeTo(kSpacingBase * scale, 0.5));
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
  /// The personal Profile's elements, and their counterparts on a
  /// friend's profile. The page is the same composition about somebody
  /// else, so every one of these stands in its counterpart's place.
  group('element for element', () {
    Finder statFigure(WidgetTester tester, Type screen) {
      final scale = figmaScale(tester.element(find.byType(screen)));
      return find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.fontSize != null &&
            (w.style!.fontSize! - kProfileStatFigureSize * scale).abs() < 0.01,
      );
    }

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScale $ts, every element stands in its place', (
        tester,
      ) async {
        await pumpMine(tester, textScale: ts);
        final lines = find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 1,
        );
        final mine = <String, Rect>{
          'ring': tester.getRect(find.byType(ProgressRing).first),
          'handle': tester.getRect(find.text('tanaka')),
          'subtitle': tester.getRect(
            find.textContaining('to your next milestone'),
          ),
          'stats': tester.getRect(statFigure(tester, ProfileScreen).first),
          'hairline 1': tester.getRect(lines.at(0)),
          'Friends': tester.getRect(find.text('Friends')),
          'hairline 2': tester.getRect(lines.at(1)),
          'Milestones': tester.getRect(find.text('Milestones')),
          'strip': tester.getRect(find.byType(ProfileStripTile).first),
          'hairline 3': tester.getRect(lines.at(2)),
          'last heading': tester.getRect(find.text('In progress')),
          'last row': tester.getRect(find.byType(ProgressRing).at(1)),
        };
        final lastLine = tester.getRect(find.text('Task 0')).bottom;

        await pumpTheirs(
          tester,
          textScale: ts,
          posts: [_milestone(0), _milestone(1), _session(0)],
        );
        final rules = find.byType(ProfileHairline);
        final theirs = <String, Rect>{
          'ring': tester.getRect(find.byType(ProgressRing).first),
          'handle': tester.getRect(find.text('cass')),
          'subtitle': tester.getRect(find.text('Friends').first),
          'stats': tester.getRect(statFigure(tester, OtherProfileScreen).first),
          'hairline 1': tester.getRect(rules.at(0)),
          'Friends': tester.getRect(
            find.descendant(
              of: find.byType(ProfileHeading),
              matching: find.text('Friends'),
            ),
          ),
          'hairline 2': tester.getRect(rules.at(1)),
          'Milestones': tester.getRect(find.text('Milestones')),
          'strip': tester.getRect(find.byType(ProfileStripTile).first),
          'hairline 3': tester.getRect(rules.at(2)),
          'last heading': tester.getRect(find.text('Posts')),
          'last row': tester.getRect(find.byType(ProfileStripTile).last),
        };

        for (final key in mine.keys) {
          expect(
            theirs[key]!.top,
            closeTo(mine[key]!.top, 0.5),
            reason: '$key top ($ts)',
          );
        }
        // The left edge, for everything that starts on the gutter rather
        // than being centred.
        for (final key in [
          'hairline 1',
          'hairline 2',
          'hairline 3',
          'Friends',
          'Milestones',
          'strip',
          'last heading',
        ]) {
          expect(
            theirs[key]!.left,
            closeTo(mine[key]!.left, 0.5),
            reason: '$key left ($ts)',
          );
        }
        // Every rule runs the same width, gutter to gutter.
        for (final key in ['hairline 1', 'hairline 2', 'hairline 3']) {
          expect(
            theirs[key]!.right,
            closeTo(mine[key]!.right, 0.5),
            reason: '$key right ($ts)',
          );
          expect(
            theirs[key]!.left,
            closeTo(mine['Friends']!.left, 0.5),
            reason: '$key starts where "Friends" does ($ts)',
          );
        }
        // Centred things are centred on the same line.
        for (final key in ['ring', 'handle', 'subtitle']) {
          expect(
            theirs[key]!.center.dx,
            closeTo(mine[key]!.center.dx, 0.5),
            reason: '$key centre ($ts)',
          );
        }
        // The ring is the same ring.
        expect(theirs['ring']!.size, mine['ring']!.size);
        // The one place the two pages may differ: the last strip ends
        // lower or higher than the personal Profile's last line by
        // exactly how much an 80 tile differs from the ring row it
        // stands in for — a point at the default size — and by nothing
        // else.
        final context = tester.element(find.byType(OtherProfileScreen));
        final overhang = kProfileStripTile * figmaScale(context) -
            profileRingRowHeight(context);
        expect(
          theirs['last row']!.bottom,
          closeTo(lastLine + overhang, 0.5),
          reason: 'the last line ($ts)',
        );
        if (ts == 1.0) {
          expect(overhang, closeTo(1, 0.5), reason: 'a point at default text');
        }
      });
    }

    testWidgets('the ring row height the clearance is built on is the real one', (
      tester,
    ) async {
      // The last section stands in the ring row's box, so the figure that
      // box is computed from cannot be allowed to drift from the widget.
      for (final ts in [0.824, 1.0, 1.235]) {
        await pumpMine(tester, textScale: ts);
        final context = tester.element(find.byType(ProfileScreen));
        final ringTop = tester.getRect(find.byType(ProgressRing).at(1)).top;
        final labelBottom = tester.getRect(find.text('Task 0')).bottom;
        expect(
          profileRingRowHeight(context),
          closeTo(labelBottom - ringTop, 0.5),
          reason: 'at $ts',
        );
      }
    });
  });

}
