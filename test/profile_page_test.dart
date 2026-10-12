import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/auth/account_screen.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/photos/models/collage.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/milestones_screen.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/ring/ring_dial.dart';

import 'support/app_viewport.dart';
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

/// The gap between strip tiles, mirrored from profile_screen.dart so the
/// arithmetic here is checking the layout rather than restating it.
const double _stripGap = 8;

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
      bool inShell = false,
      List<Photo> milestonePhotos = const [],
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
            collagesListProvider.overrideWith(
              (ref) async => milestonePhotos.isEmpty
                  ? const <Collage>[]
                  : [
                      Collage(
                        taskId: 't',
                        milestoneHours: 20,
                        photoIds: [for (final p in milestonePhotos) p.id],
                        edited: false,
                      ),
                    ],
            ),
            collagePhotosProvider.overrideWith(
              (ref, key) async => milestonePhotos,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            // A tab screen's body is the screen less the tab bar and the
            // bottom inset — forget that and the fold reads 74 too generous.
            home: inShell
                ? Scaffold(
                    body: const ProfileScreen(),
                    bottomNavigationBar: const SizedBox(
                      height: kTabBarHeight + kRefBottomInset,
                    ),
                  )
                : const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The hero and the in-progress tiles are all ProgressRings; tell them
    /// apart by DIAMETER rather than by tree order.
    Finder ringFinder(WidgetTester tester, double reference) {
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      return find.byWidgetPredicate(
        (w) => w is ProgressRing && (w.size - reference * scale).abs() < 0.01,
      );
    }

    ProgressRing ringOfSize(WidgetTester tester, double reference) =>
        tester.widget<ProgressRing>(ringFinder(tester, reference).first);

    Iterable<ProgressRing> ringsOfSize(WidgetTester tester, double reference) =>
        tester.widgetList<ProgressRing>(ringFinder(tester, reference));

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

    testWidgets('the hero is Ø128, at its measured proportions', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        recent: [_photo(3000)],
        tasks: [_task('Spanish', seconds: 3600)],
      );
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      final hero = ringOfSize(tester, 128);

      expect(hero.size, closeTo(128 * scale, 0.01));
      // The 6 stroke and 104 photo it was measured at on a 132 ring, kept as
      // shares of the diameter rather than re-picked.
      expect(hero.stroke, closeTo(128 * scale * 6 / 132, 0.01));
      expect(
        tester.getSize(find.byType(ClipOval)).height,
        closeTo(128 * scale * 104 / 132, 0.01),
      );
      expectNoOverflow(tester);
    });

    testWidgets('an in-progress ring is Ø54 at the thin weight', (
      tester,
    ) async {
      await pumpProfile(tester, tasks: [_task('Spanish', seconds: 3600)]);
      // The hero is first in the tree; the tile's ring follows it.
      final tileFinder = find.byType(ProgressRing).last;
      final scale = figmaScale(tester.element(tileFinder));
      final ring = tester.widget<ProgressRing>(tileFinder);

      expect(ring.size, closeTo(54 * scale, 0.001));
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

    testWidgets('in progress is four slots, however many tasks there are', (
      tester,
    ) async {
      // Four rings and no scroller: the count beside the heading carries the
      // total, so the row does not have to.
      await pumpProfile(
        tester,
        tasks: [for (var i = 0; i < 8; i++) _task('T$i', seconds: 3600)],
      );
      expect(ringsOfSize(tester, 54), hasLength(4));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      final rings = ringFinder(tester, 54);
      final firstTop = tester.getTopLeft(rings.first).dy;
      for (var i = 1; i < 4; i++) {
        expect(tester.getTopLeft(rings.at(i)).dy, closeTo(firstTop, 0.5));
      }
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
      // A bare number, like the Friends and Milestones counts above it.
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('active'), findsNothing);
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

    testWidgets('the milestone count is the same figure in both places', (
      tester,
    ) async {
      // 21h is one milestone, 65h is three: four in total. The totals figure
      // and the doorway count are now the same provider, so there is one
      // number rather than a stat and a collage tally that drift apart.
      //
      // Four rather than three deliberately: the local habits seed makes the
      // day streak 3, and a figure that collides with it would pass whatever
      // the doorway said.
      await pumpProfile(
        tester,
        tasks: [
          _task('Spanish', seconds: 21 * 3600),
          _task('Golf', seconds: 65 * 3600),
        ],
      );
      expect(find.text('milestones'), findsOneWidget); // the totals' label
      // Twice: once as the totals figure, once as the doorway's count.
      expect(find.text('4'), findsNWidgets(2));
      expectNoOverflow(tester);
    });

    testWidgets('a milestone with no collage behind it still counts', (
      tester,
    ) async {
      // The doorway used to count saved collages, so a milestone reached with
      // nothing captured in its band went missing from it. There is no photo
      // store in this test at all, so every collage is absent.
      // Two tasks so the in-progress count is 2 and cannot be mistaken for
      // the milestone figure.
      await pumpProfile(
        tester,
        tasks: [
          _task('Spanish', seconds: 21 * 3600),
          _task('Piano', seconds: 3600),
        ],
      );
      expect(find.text('1'), findsNWidgets(2)); // totals figure + doorway
      expect(find.text('milestone'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('the milestone strip is four full-width squares', (
      tester,
    ) async {
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        inShell: true,
        // No recent capture, so the hero shows a monogram and every
        // SondrPhoto on the page belongs to the strip.
        milestonePhotos: [for (var i = 0; i < 4; i++) _photo(1000 + i)],
      );
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      final tiles = find.byType(SondrPhoto);
      expect(tiles, findsNWidgets(4));

      final sizes = [
        for (var i = 0; i < 4; i++) tester.getSize(tiles.at(i)),
      ];
      // Square, and all four the same.
      for (final size in sizes) {
        expect(size.width, closeTo(size.height, 0.01));
        expect(size.width, closeTo(sizes.first.width, 0.01));
      }
      // Bigger than the 34 they used to be, and they fill the content width:
      // four tiles plus three gaps is the page less its gutters.
      expect(sizes.first.width, greaterThan(60 * scale));
      final content = 393 * scale - 2 * 24 * scale;
      expect(
        sizes.first.width * 4 + _stripGap * scale * 3,
        closeTo(content, 0.5),
      );
      // Flush to the gutter, with no inset of their own.
      expect(tester.getTopLeft(tiles.first).dx, closeTo(24 * scale, 0.5));
      expect(
        tester.getTopRight(tiles.at(3)).dx,
        closeTo(393 * scale - 24 * scale, 0.5),
      );
      expectNoOverflow(tester);
    });

    testWidgets('a short collage fills the first slots and leaves the rest', (
      tester,
    ) async {
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        inShell: true,
        milestonePhotos: [for (var i = 0; i < 2; i++) _photo(2000 + i)],
      );
      final tiles = find.byType(SondrPhoto);
      expect(tiles, findsNWidgets(2));
      // Still slot-sized, not stretched across the page.
      final four = (393 - 48 - _stripGap * 3) / 4;
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      expect(tester.getSize(tiles.first).width, closeTo(four * scale, 0.5));
      expectNoOverflow(tester);
    });

    testWidgets('the strip still opens the Milestones page', (tester) async {
      await pumpProfile(
        tester,
        milestonePhotos: [for (var i = 0; i < 4; i++) _photo(3000 + i)],
      );
      await tester.tap(find.byType(SondrPhoto).first);
      await tester.pumpAndSettle();
      expect(find.byType(MilestonesScreen), findsOneWidget);
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

      // The line HUGS the heading below it — 11 under the line against the
      // 22 break above — so the break belongs to what follows it.
      expect(below, closeTo(11 * scale, 0.5));
      expect(above, closeTo(22 * scale, 0.5));
      expect(above, greaterThan(below));
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

    /// The iPhone 13 Pro the composition was calibrated on: 390x844, a 47
    /// top inset, and the tab bar's top edge at 770, which leaves 723 of
    /// content. Measured here rather than assumed anywhere.
    const double w13 = 390;
    const double h13 = 844;
    const double top13 = 47;
    const double tabBarTop13 = 770;

    /// Pumps the page on that device and returns every gap the composition is
    /// specified in, so a failure says WHICH gap moved.
    Future<Map<String, double>> compose(WidgetTester tester) async {
      tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: top13 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);

      await pumpProfile(
        tester,
        inShell: true,
        tasks: [for (var i = 0; i < 6; i++) _task('Task $i', seconds: 45900)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
        milestonePhotos: [for (var i = 0; i < 4; i++) _photo(1000 + i)],
      );

      final lines = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 1,
      );
      expect(lines, findsNWidgets(4)); // three sections, plus the account's
      final photos = find.byType(SondrPhoto);
      final rings = find.byType(ProgressRing);

      double top(Finder f) => tester.getTopLeft(f).dy;
      double bottom(Finder f) => tester.getBottomLeft(f).dy;

      return {
        'emblemTop': top(rings.first),
        'statsBottom': bottom(find.text('day streak')),
        'break1': top(lines.at(0)) - bottom(find.text('day streak')),
        'hl1ToFriends': top(find.text('Friends')) - bottom(lines.at(0)),
        'break2': top(lines.at(1)) - bottom(find.text('Friends')),
        'hl2ToMilestones':
            top(find.text('Milestones')) - bottom(lines.at(1)),
        'milestonesToPhotos':
            top(photos.first) - bottom(find.text('Milestones')),
        'break3': top(lines.at(2)) - bottom(photos.last),
        'hl3ToInProgress':
            top(find.text('In progress')) - bottom(lines.at(2)),
        'inProgressToRings':
            top(rings.at(1)) - bottom(find.text('In progress')),
        'ringsBottom': bottom(find.text('Task 0')),
        'clearance': tabBarTop13 - bottom(find.text('Task 0')),
        'accountTop': top(find.byType(AccountBody)),
        'photoTile': tester.getSize(photos.first).width,
      };
    }

    testWidgets('1. the photos are exactly four tiles in one row', (
      tester,
    ) async {
      await compose(tester);
      final photos = find.byType(SondrPhoto);
      expect(photos, findsNWidgets(4));
      // One row: all four share a top edge.
      final firstTop = tester.getTopLeft(photos.first).dy;
      for (var i = 1; i < 4; i++) {
        expect(tester.getTopLeft(photos.at(i)).dy, closeTo(firstTop, 0.5));
      }
      expectNoOverflow(tester);
    });

    testWidgets('2. the emblem sits down the screen, not on the padlock', (
      tester,
    ) async {
      final m = await compose(tester);
      // 92 rather than 120: the real text metrics ate 34 of the slack the
      // top margin was carrying, so the emblem sits that much higher.
      expect(m['emblemTop'], inInclusiveRange(92, 145));
      expectNoOverflow(tester);
    });

    testWidgets('3. the three section breaks are 22', (tester) async {
      final m = await compose(tester);
      for (final k in ['break1', 'break2', 'break3']) {
        expect(m[k], closeTo(22, 3), reason: k);
      }
      expectNoOverflow(tester);
    });

    testWidgets('4. hairline to heading is 11, and the two content gaps', (
      tester,
    ) async {
      final m = await compose(tester);
      for (final k in ['hl1ToFriends', 'hl2ToMilestones', 'hl3ToInProgress']) {
        expect(m[k], closeTo(11, 2), reason: k);
      }
      expect(m['milestonesToPhotos'], closeTo(26, 3));
      expect(m['inProgressToRings'], closeTo(20, 3));
      expectNoOverflow(tester);
    });

    testWidgets('5. VOID GUARD: no gap between sections exceeds 32', (
      tester,
    ) async {
      final m = await compose(tester);
      // Everything from the stats row down to the rings. The top margin and
      // the bottom clearance are margins, not gaps, so they are excluded.
      const gaps = [
        'break1',
        'hl1ToFriends',
        'break2',
        'hl2ToMilestones',
        'milestonesToPhotos',
        'break3',
        'hl3ToInProgress',
        'inProgressToRings',
      ];
      for (final k in gaps) {
        expect(m[k], lessThanOrEqualTo(32), reason: 'gap $k is a void');
      }
      expectNoOverflow(tester);
    });

    testWidgets('6. the rings clear the tab bar by 22 to 38', (tester) async {
      final m = await compose(tester);
      expect(m['ringsBottom'], inInclusiveRange(tabBarTop13 - 38, tabBarTop13 - 22));
      expectNoOverflow(tester);
    });

    testWidgets('7. the account block stays below the fold', (tester) async {
      final m = await compose(tester);
      expect(m['accountTop'], greaterThanOrEqualTo(tabBarTop13));
      expectNoOverflow(tester);
    });

    testWidgets('the section headings are the Heading token, counts 14', (
      tester,
    ) async {
      await compose(tester);
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      for (final heading in ['Friends', 'Milestones', 'In progress']) {
        final style = tester.widget<Text>(find.text(heading)).style!;
        expect(style.fontSize, closeTo(20 * scale, 0.01), reason: heading);
        expect(style.fontWeight, FontWeight.w700, reason: heading);
      }
      // Six active tasks, so the in-progress count reads 6 — plainly.
      expect(
        tester.widget<Text>(find.text('6')).style!.fontSize,
        closeTo(14 * scale, 0.01),
      );
      expect(find.textContaining('active'), findsNothing);
      expectNoOverflow(tester);
    });

    testWidgets('the emblem and its figures stay together at the top', (
      tester,
    ) async {
      // The free space goes BETWEEN the sections, never inside the cluster.
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        inShell: true,
        tasks: [_task('Spanish', seconds: 45900)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
      );
      // The foot of the hero BLOCK — the ring, then the handle, then the
      // countdown, all of which live inside _HeroEmblem.
      final heroBottom = tester
          .getBottomLeft(find.textContaining('to your next milestone'))
          .dy;
      // 45900s is 12.75 lifetime hours, so the first figure reads 13.
      final statsTop = tester.getTopLeft(find.text('13')).dy;
      final cluster = statsTop - heroBottom;

      // The section break below it — the widest gap the composition allows
      // anywhere on the page.
      final lines = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 1,
      );
      final sectionBreak =
          tester.getTopLeft(lines.first).dy -
          tester.getBottomLeft(find.text('day streak')).dy;

      // The cluster keeps its own small gap while the sections take the free
      // space — that is the whole claim. (It measures 32 rather than the
      // declared 24 because of the figures' line box, and it measures the
      // same with the distribution turned off: structural, not drift.)
      expect(cluster, greaterThan(0));
      expect(cluster, lessThanOrEqualTo(sectionBreak + 12));
      expect(cluster, lessThanOrEqualTo(40));
      expectNoOverflow(tester);
    });

    testWidgets('the account block is off-screen at the top of the scroll', (
      tester,
    ) async {
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        tasks: [_task('Spanish', seconds: 3600)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
        inShell: true,
      );

      // A tab screen's body is the screen less the tab bar and the bottom
      // inset. Nothing of the account block may be inside it at rest.
      final fold = refBodyHeight();
      expect(
        tester.getTopLeft(find.byType(AccountBody)).dy,
        greaterThanOrEqualTo(fold),
      );
      // And the content above it still ends inside the first screen.
      expect(tester.getTopLeft(find.text('In progress')).dy, lessThan(fold));
      expectNoOverflow(tester);
    });

    testWidgets('scrolling down brings the account block into view', (
      tester,
    ) async {
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        tasks: [_task('Spanish', seconds: 3600)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
        inShell: true,
      );
      final before = tester.getTopLeft(find.byType(AccountBody)).dy;

      await tester.drag(find.byType(ProfileScreen), const Offset(0, -260));
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(find.byType(AccountBody)).dy;
      expect(after, lessThan(before));
      // Up past the fold, so it is genuinely on screen now.
      expect(after, lessThan(refBodyHeight()));
      expectNoOverflow(tester);
    });

    testWidgets('the fold follows the viewport, not a fixed number', (
      tester,
    ) async {
      // Taller device: the account block has to move WITH the fold, which a
      // hard-coded spacer could not do.
      tester.view.physicalSize = const Size(430 * 3, 932 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpProfile(
        tester,
        tasks: [_task('Spanish', seconds: 3600)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
        inShell: true,
      );
      final body = 932 - (kTabBarHeight + kRefBottomInset);
      expect(
        tester.getTopLeft(find.byType(AccountBody)).dy,
        greaterThanOrEqualTo(body - 1),
      );
      expectNoOverflow(tester);
    });
  });
}
