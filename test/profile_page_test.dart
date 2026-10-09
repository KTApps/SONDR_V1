import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/theme/spacing.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/ring/ring_dial.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';

/// The profile page reorganised around one hero emblem.
///
/// Two things here are rules rather than preferences, and both are asserted:
/// a PROGRESS ring is grey (white belongs to a milestone already finished),
/// and the page is borderless — no filled cards, no chevrons.

/// A task list we choose, so "nearest milestone" can be checked exactly
/// instead of against whatever the local seed happens to hold.
class _FakeTasks implements TasksRepository {
  _FakeTasks(this.tasks);

  final List<Task> tasks;

  @override
  Future<List<Task>> fetchAll() async => tasks;

  @override
  Future<Task> create(String name) async => throw UnimplementedError();

  @override
  Future<void> save(Task task) async {}
}

Task _task(String name, {required int seconds, bool archived = false}) => Task(
  id: name,
  name: name,
  secondsByDay: {'2026-10-01': seconds},
  archived: archived,
);

Photo _photo(int micros) => Photo(
  taskId: 't',
  taskName: 'Golf',
  dayKey: '2026-10-01',
  timestamp: micros,
  sessionSeconds: 60,
  photoUrl: 'https://example.invalid/$micros.jpg',
  storagePath: 'users/me/photos/$micros.jpg',
);

/// Swallows the one error this page cannot avoid in a unit test, and only
/// that one.
///
/// The account block reads `FirebaseAuth.instance`, which throws with no
/// Firebase initialised. It throws once per build of that block, and the page
/// settles over several frames (the in-progress row is a ListView), so
/// draining them afterwards is not enough — a second arriving while the first
/// is still pending fails the test outright. Filtering it at the source
/// leaves every OTHER error, an overflow included, failing as it should.
void ignoreFirebaseAbsence() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('No Firebase App')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Fails if the page overflowed. Anything else real has already failed the
/// test through [FlutterError.onError].
void expectNoOverflow(WidgetTester tester) {
  final thrown = <Object>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    thrown.add(e);
  }
  expect(thrown.where((e) => e.toString().contains('overflowed')), isEmpty);
}

void main() {
  group('the nearest milestone', () {
    ProviderContainer withTasks(List<Task> tasks) {
      final c = ProviderContainer(
        overrides: [tasksRepositoryProvider.overrideWithValue(_FakeTasks(tasks))],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('is the task furthest through its band, not the biggest total',
        () async {
      // Spanish is 1h away from 20h; Golf has four times the hours but has
      // just reset past 80h, so it is 19h away.
      final c = withTasks([
        _task('Spanish', seconds: 19 * 3600),
        _task('Golf', seconds: 81 * 3600),
      ]);
      await c.read(tasksProvider.future);

      final next = c.read(nextMilestoneProvider)!;
      expect(next.task.name, 'Spanish');
      expect(next.hoursRemaining, 1);
      expect(next.progress, closeTo(0.95, 0.001));
    });

    test('rounds the hours remaining UP, never to zero', () async {
      final c = withTasks([_task('Spanish', seconds: 19 * 3600 + 1800)]);
      await c.read(tasksProvider.future);
      // Half an hour to go reads as 1h, never 0h.
      expect(c.read(nextMilestoneProvider)!.hoursRemaining, 1);
    });

    test('is null when there is no active task', () async {
      final c = withTasks(const []);
      await c.read(tasksProvider.future);
      expect(c.read(nextMilestoneProvider), isNull);
    });

    test('ignores an archived task, however close it is', () async {
      final c = withTasks([
        _task('Spanish', seconds: 19 * 3600, archived: true),
        _task('Piano', seconds: 2 * 3600),
      ]);
      await c.read(tasksProvider.future);
      expect(c.read(nextMilestoneProvider)!.task.name, 'Piano');
      expect(c.read(nextMilestoneProvider)!.hoursRemaining, 18);
    });
  });

  group('the page', () {
    Future<void> pumpProfile(
      WidgetTester tester, {
      List<Task> tasks = const [],
      List<Photo> recent = const [],
      Profile? profile,
    }) async {
      ignoreFirebaseAbsence();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('me'),
            authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
            tasksRepositoryProvider.overrideWithValue(_FakeTasks(tasks)),
            currentProfileProvider.overrideWith((ref) async => profile),
            galleryPreviewProvider.overrideWith(
              (ref) async => (recent: recent, total: recent.length),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the hero ring is a PROGRESS ring, in the progress grey', (
      tester,
    ) async {
      await pumpProfile(tester, tasks: [_task('Spanish', seconds: 19 * 3600)]);

      // ProgressRing fills with ringFillInner by construction. The point of
      // the assertion is that the hero is NOT a RingDial, which is what the
      // Milestones page uses to paint a finished milestone white.
      expect(find.byType(ProgressRing), findsWidgets);
      expect(find.byType(RingDial), findsNothing);

      final tokens = GreyscaleTokens.of(
        tester.element(find.byType(ProgressRing).first),
      );
      expect(tokens.ringFillInner, const Color(0xFFADADAD));
      expect(tokens.textPrimary, const Color(0xFFFAFAFA));
      expectNoOverflow(tester);
    });

    testWidgets('the hero is Ø132 with a 6 stroke and a Ø104 photo', (
      tester,
    ) async {
      // Four numbers that only work together: 132 − 2×6 leaves 120, and a 104
      // photo centred in that IS the 8 gap the reference asks for.
      await pumpProfile(
        tester,
        recent: [_photo(3000)],
        tasks: [_task('Spanish', seconds: 3600)],
      );
      final heroFinder = find.byType(ProgressRing).first;
      final scale = figmaScale(tester.element(heroFinder));
      final hero = tester.widget<ProgressRing>(heroFinder);

      expect(hero.size, closeTo(132 * scale, 0.001));
      expect(hero.stroke, closeTo(6 * scale, 0.001));
      expect(
        tester.getSize(find.byType(ClipOval)).height,
        closeTo(104 * scale, 0.001),
      );
      // The hole left by the stroke, minus the photo, halved: the gap.
      final gap = ((hero.size - 2 * hero.stroke!) - 104 * scale) / 2;
      expect(gap, closeTo(8 * scale, 0.001));
      expectNoOverflow(tester);
    });

    testWidgets('an in-progress ring is Ø56 at the thin weight', (
      tester,
    ) async {
      await pumpProfile(tester, tasks: [_task('Spanish', seconds: 3600)]);
      // The hero is first in the tree; the tile's ring follows it.
      final tileFinder = find.byType(ProgressRing).last;
      final scale = figmaScale(tester.element(tileFinder));
      final ring = tester.widget<ProgressRing>(tileFinder);

      expect(ring.size, closeTo(56 * scale, 0.001));
      expect(ring.stroke, closeTo(3 * scale, 0.001));
      expect(ring.stroke, closeTo(thinRingStroke(ring.size), 0.001));
      expectNoOverflow(tester);
    });

    testWidgets('a nonzero ring is never empty, and never closed', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        tasks: [
          // 12 minutes of a 20-hour band, and one minute short of 20 hours.
          _task('Spanish', seconds: 12 * 60),
          _task('Piano', seconds: 20 * 3600 - 60),
        ],
      );
      final rings = tester
          .widgetList<ProgressRing>(find.byType(ProgressRing))
          .toList();
      // Hero first, then the two tiles in order.
      expect(rings[1].progress, kProgressFloor);
      expect(rings[2].progress, kProgressCeiling);
      expectNoOverflow(tester);
    });

    testWidgets('in progress is ONE row however many tasks there are', (
      tester,
    ) async {
      Finder strip() => find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );

      await pumpProfile(
        tester,
        tasks: [for (var i = 0; i < 2; i++) _task('T$i', seconds: 3600)],
      );
      final twoTasks = tester.getSize(strip()).height;

      await pumpProfile(
        tester,
        tasks: [for (var i = 0; i < 8; i++) _task('T$i', seconds: 3600)],
      );
      // Eight tasks, same height: the row grows sideways, never downward.
      expect(tester.getSize(strip()).height, twoTasks);
      expectNoOverflow(tester);
    });

    testWidgets('the count reads the non-archived tasks', (tester) async {
      await pumpProfile(
        tester,
        tasks: [
          _task('Spanish', seconds: 3600),
          _task('Piano', seconds: 3600),
          _task('Golf', seconds: 3600, archived: true),
        ],
      );
      expect(find.text('2 active'), findsOneWidget);
      expect(find.text('3 active'), findsNothing);
      // And the archived one is not in the row either.
      expect(find.text('Golf'), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('the subline counts down to the nearest milestone', (
      tester,
    ) async {
      await pumpProfile(tester, tasks: [_task('Spanish', seconds: 19 * 3600)]);
      expect(find.text('1h to your next milestone'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('with no task the ring is empty and the line is neutral', (
      tester,
    ) async {
      await pumpProfile(tester);
      expect(find.text('No task in progress.'), findsOneWidget);
      final ring = tester.widget<ProgressRing>(find.byType(ProgressRing));
      expect(ring.progress, 0);
      expectNoOverflow(tester);
    });

    testWidgets('the handle sits in the hero', (tester) async {
      await pumpProfile(
        tester,
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
      );
      expect(find.text('@tanaka'), findsOneWidget);
      // And is not repeated in the account block below.
      expect(find.text('Handle'), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('no handle yet means no faked one', (tester) async {
      await pumpProfile(tester);
      expect(find.textContaining('@'), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('the centre is the monogram until a photo exists', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        profile: const Profile(
          uid: 'me',
          username: 'tanaka',
          displayName: 'Tanaka Bere',
        ),
      );
      expect(find.text('T'), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('the monogram falls back to the handle', (tester) async {
      await pumpProfile(
        tester,
        profile: const Profile(uid: 'me', username: 'zed', displayName: ''),
      );
      expect(find.text('Z'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('the newest capture takes the centre once there is one', (
      tester,
    ) async {
      // galleryPreview's `recent` is newest-first, so the head of the list is
      // the newest capture across every task.
      await pumpProfile(
        tester,
        recent: [_photo(3000), _photo(2000)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
      );
      expect(find.byType(ClipOval), findsOneWidget);
      expect(find.text('T'), findsNothing); // the monogram has given way
      expectNoOverflow(tester);
    });

    testWidgets('an in-progress ring names the target it climbs to', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        tasks: [
          _task('Spanish', seconds: 19 * 3600),
          _task('Golf', seconds: 21 * 3600),
        ],
      );
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('Golf'), findsOneWidget);
      // Targets, not totals: Spanish climbs to 20h, Golf to 40h.
      expect(find.text('20h'), findsOneWidget);
      expect(find.text('40h'), findsOneWidget);
      expect(find.text('19h'), findsNothing);
      expect(find.text('21h'), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('nothing is carded, and nothing wears a chevron', (
      tester,
    ) async {
      await pumpProfile(tester, tasks: [_task('Spanish', seconds: 3600)]);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.people_outline), findsNothing);
      // A filled rounded card reads as a button; the rows are bare now.
      expect(find.byType(InkWell), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('a section break sits closer to what it follows', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        tasks: [_task('Spanish', seconds: 3600)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
      );
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      final hairlines = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 1,
      );
      // Friends, Milestones, In progress, Account.
      expect(hairlines, findsNWidgets(4));

      // The first break: the stats row above it ('day streak' is the middle
      // stat's label, and the three stat columns are the same height), and
      // "Friends" below.
      final line = hairlines.first;
      final above =
          tester.getTopLeft(line).dy - tester.getBottomLeft(find.text('day streak')).dy;
      final below =
          tester.getTopLeft(find.text('Friends')).dy -
          tester.getBottomLeft(line).dy;

      // Asymmetric on purpose: the heading hugs the content it introduces.
      expect(above, closeTo(kSpacingBase * scale, 0.01));
      expect(below, closeTo(kSpacingSection * scale, 0.01));
      expect(above, lessThan(below));
      expectNoOverflow(tester);
    });

    testWidgets('the sections run in order, with the account block last', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        tasks: [_task('Spanish', seconds: 3600)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
      );

      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('@tanaka'), lessThan(y('Friends')));
      expect(y('Friends'), lessThan(y('Milestones')));
      expect(y('Milestones'), lessThan(y('In progress')));
      expectNoOverflow(tester);
    });
  });
}
