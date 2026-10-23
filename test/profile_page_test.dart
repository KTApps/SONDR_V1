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
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/profile_repository.dart';
import 'package:sondr/features/photos/models/collage.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/photo_viewer.dart';
import 'package:sondr/features/photos/milestones_screen.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/milestone_strip.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/profile/profile_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/ring/ring_dial.dart';

import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/timer/home_metrics.dart';

import 'support/app_viewport.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';

import 'tiny_png.dart';

/// The profile page reorganised around one hero emblem.
///
/// Two things here are rules rather than preferences, and both are asserted:
/// a PROGRESS ring is grey (white belongs to a milestone already finished),
/// and the page is borderless — no filled cards, no chevrons.

/// A task list we choose, so "nearest milestone" can be checked exactly
/// instead of against whatever the local seed happens to hold.
class _FakeTasks implements TasksRepository {
  @override
  Future<void> delete(String taskId) async {}

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
      bool inShell = false,
      User? account,
      List<Photo> milestonePhotos = const [],
      double textScale = 1.0,
      List<Friendship> friendships = const [],
    }) async {
      ignoreFirebaseAbsence();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('me'),
            authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
            // Always overridden: without it the account block reaches for
            // FirebaseAuth and renders an error widget, so nothing inside
            // it could be measured. Given an account it renders the
            // signed-in face; given none, a guest's.
            authRepositoryProvider.overrideWithValue(_Auth(account)),
            tasksRepositoryProvider.overrideWithValue(_FakeTasks(tasks)),
            currentProfileProvider.overrideWith((ref) async => profile),
            galleryPreviewProvider.overrideWith((ref) async => recent),
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
            milestoneStripProvider.overrideWith(
              (ref) async => [
                for (final p in milestonePhotos)
                  MilestoneStripEntry(
                    task: _task('t', seconds: 20 * 3600),
                    bandHours: 20,
                    photo: p,
                    crossedAt: p.timestamp,
                    detail: BandDetail(collage: null, photos: [p]),
                  ),
              ],
            ),
            friendshipsProvider.overrideWith(
              (ref) => Stream.value(friendships),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
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
      // The app's one ring weight, not the 6 this ring was measured at. It
      // grows INWARD — the painter insets by half the stroke — so the outer
      // diameter is untouched and so is the photo, still the 104 share of a
      // 132 ring it was measured at.
      expect(hero.stroke, closeTo(ringStroke(scale), 0.01));
      expect(
        tester.getSize(find.byType(ClipOval)).height,
        closeTo(128 * scale * 104 / 132, 0.01),
      );
      expectNoOverflow(tester);
    });

    testWidgets('an in-progress ring matches the Milestones page ring', (
      tester,
    ) async {
      await pumpProfile(tester, tasks: [_task('Spanish', seconds: 3600)]);
      // The hero is first in the tree; the tile's ring follows it.
      final tileFinder = find.byType(ProgressRing).last;
      final scale = figmaScale(tester.element(tileFinder));
      final ring = tester.widget<ProgressRing>(tileFinder);

      // Ø56 at the app's one ring weight — the same two numbers _DoneRing
      // uses for a task row on the Milestones page.
      expect(ring.size, closeTo(56 * scale, 0.001));
      expect(ring.stroke, closeTo(ringStroke(scale), 0.001));
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
      // By name, not by position: the tiles are alphabetical now, and this
      // test is about the clamp rather than the order.
      double ringFor(String task) => tester
          .widget<ProgressRing>(
            find.descendant(
              of: find.ancestor(
                of: find.text(task),
                matching: find.byType(Column),
              ).first,
              matching: find.byType(ProgressRing),
            ),
          )
          .progress;
      expect(ringFor('Spanish'), kProgressFloor);
      expect(ringFor('Piano'), kProgressCeiling);
      expectNoOverflow(tester);
    });

    testWidgets('in progress scrolls sideways through every task', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        tasks: [for (var i = 0; i < 8; i++) _task('T$i', seconds: 3600)],
      );
      // All eight are there, in one row that scrolls — not a fixed four.
      expect(ringsOfSize(tester, 56), hasLength(8));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
      final rings = ringFinder(tester, 56);
      final firstTop = tester.getTopLeft(rings.first).dy;
      for (var i = 1; i < 8; i++) {
        expect(tester.getTopLeft(rings.at(i)).dy, closeTo(firstTop, 0.5));
      }
      expectNoOverflow(tester);
    });

    testWidgets('the ring row is one tile tall whatever the count', (
      tester,
    ) async {
      Finder strip() => find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );

      await pumpProfile(
        tester,
        tasks: [for (var i = 0; i < 2; i++) _task('T$i', seconds: 3600)],
      );
      final twoTasks = tester.getSize(strip()).height;

      await pumpProfile(
        tester,
        tasks: [for (var i = 0; i < 9; i++) _task('T$i', seconds: 3600)],
      );
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
      expect(find.text('tanaka'), findsOneWidget);
      // Bare, with no "@" in front of it: your own page is not a mention.
      expect(find.textContaining('@'), findsNothing);
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

    testWidgets('the milestone strip scrolls on fixed squares', (
      tester,
    ) async {
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        inShell: true,
        milestonePhotos: [for (var i = 0; i < 6; i++) _photo(1000 + i)],
      );
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      final tiles = find.byType(SondrPhoto);

      // Every photo the collage holds, reached by dragging rather than by
      // shrinking the tiles to suit.
      expect(tiles, findsNWidgets(6));
      // The tiles themselves sit inside a horizontal scroller — asserted of
      // the strip rather than of the page, which also has one for the rings.
      expect(
        find.ancestor(
          of: tiles.first,
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsOneWidget,
      );

      for (var i = 0; i < 6; i++) {
        final size = tester.getSize(tiles.at(i));
        expect(size.width, closeTo(80 * scale, 0.01));
        expect(size.height, closeTo(80 * scale, 0.01));
      }
      // One row: all six share a top edge.
      final firstTop = tester.getTopLeft(tiles.first).dy;
      for (var i = 1; i < 6; i++) {
        expect(tester.getTopLeft(tiles.at(i)).dy, closeTo(firstTop, 0.5));
      }
      // Flush to the gutter, with no inset of its own.
      expect(tester.getTopLeft(tiles.first).dx, closeTo(24 * scale, 0.5));
      expectNoOverflow(tester);
    });

    testWidgets('a short collage is simply fewer tiles, same size', (
      tester,
    ) async {
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        inShell: true,
        milestonePhotos: [for (var i = 0; i < 2; i++) _photo(2000 + i)],
      );
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      final tiles = find.byType(SondrPhoto);
      expect(tiles, findsNWidgets(2));
      // Not stretched to fill the width — the same square as a full collage.
      expect(tester.getSize(tiles.first).width, closeTo(80 * scale, 0.01));
      expectNoOverflow(tester);
    });

    testWidgets('the heading opens the Milestones page on its default lens', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        milestonePhotos: [for (var i = 0; i < 4; i++) _photo(3000 + i)],
      );
      await tester.tap(find.text('Milestones'));
      await tester.pumpAndSettle();
      expect(find.byType(MilestonesScreen), findsOneWidget);
      // The page itself, not a journey: both lenses are on screen.
      expect(find.text('Photos'), findsOneWidget);
    });

    testWidgets('a photo in the strip opens the viewer on it, not the page', (
      tester,
    ) async {
      final factoryBefore = photoImageProviderFactory;
      photoImageProviderFactory = (_) => MemoryImage(tinyPng);
      addTearDown(() => photoImageProviderFactory = factoryBefore);
      await pumpProfile(
        tester,
        milestonePhotos: [for (var i = 0; i < 4; i++) _photo(3000 + i)],
      );
      await tester.tap(find.byType(SondrPhoto).first);
      await tester.pumpAndSettle();
      // The photo itself, large, with its stretch (the harness hands each
      // milestone a one-photo stretch) — and no journey pushed underneath.
      final viewer = tester.widget<PhotoViewer>(find.byType(PhotoViewer));
      expect(viewer.photos.map((p) => p.id), [_photo(3000).id]);
      expect(viewer.index, 0);
      expect(find.byType(MilestonesScreen, skipOffstage: false), findsNothing);
      expect(find.text('Close'), findsOneWidget);
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

      // The line HUGS the heading below it — 14 under the line against the
      // 22 break above — so the break belongs to what follows it.
      expect(below, closeTo(14 * scale, 0.5));
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
      expect(y('tanaka'), lessThan(y('Friends')));
      expect(y('Friends'), lessThan(y('Milestones')));
      expect(y('Milestones'), lessThan(y('In progress')));
      expectNoOverflow(tester);
    });

    /// The iPhone 13 Pro the composition was calibrated on: 390x844, a 47
    /// top inset, and the tab bar's top edge at 770, which leaves 723 of
    /// content. Measured here rather than assumed anywhere.
    const double w13 = 390;
    /// The in-progress tile's width, mirrored from profile_screen.dart so the
    /// ring's own left edge can be worked back to the tile's.
    const double ringTile = 72;
    const double h13 = 844;
    const double top13 = 47;
    const double tabBarTop13 = 770;

    /// Pumps the page on that device and returns every gap the composition is
    /// specified in, so a failure says WHICH gap moved.
    /// Two friendships, one accepted and one waiting, so the Friends row
    /// renders its count AND its "1 new" — the states that put anything
    /// beside that heading at all.
    List<Friendship> friendSeed() => [
      const Friendship(
        id: 'me_a',
        users: ['me', 'a'],
        requestedBy: 'me',
        status: FriendshipStatus.accepted,
        profiles: {},
      ),
      const Friendship(
        id: 'b_me',
        users: ['b', 'me'],
        requestedBy: 'b',
        status: FriendshipStatus.pending,
        profiles: {},
      ),
    ];

    Future<Map<String, double>> compose(
      WidgetTester tester, {
      double textScale = 1.0,
      bool withFriends = false,
    }) async {
      tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: top13 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);

      await pumpProfile(
        tester,
        inShell: true,
        textScale: textScale,
        friendships: withFriends ? friendSeed() : const [],
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

      final handle = find.text('tanaka');
      final subline = find.textContaining('to your next milestone');

      return {
        'emblemTop': top(rings.first),
        'emblemToHandle': top(handle) - bottom(rings.first),
        'handleToSubline': top(subline) - bottom(handle),
        // Six tasks at 12.75h each is 76.5 lifetime hours, so the first
        // figure reads 76: the figure FLOORS, because an hour you have
        // not finished is not an hour. (It read 77 until the rounding was
        // fixed.) Every figure starts at the row's top.
        'sublineToStats': top(find.text('76')) - bottom(subline),
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
        'statsTop': top(find.text('76')),
        'labelCentre': tester.getRect(find.text('Task 0')).center.dy,
        'homeCta': homeCtaCentreY(tester.element(find.byType(ProfileScreen))),
        'clearance': tabBarTop13 - bottom(find.text('Task 0')),
        'accountTop': top(find.byType(AccountBody)),
        'photoTile': tester.getSize(photos.first).width,
        'friendsLeft': tester.getTopLeft(find.text('Friends')).dx,
        'milestonesLeft': tester.getTopLeft(find.text('Milestones')).dx,
        'inProgressLeft': tester.getTopLeft(find.text('In progress')).dx,
        'hairlineLeft': tester.getTopLeft(lines.at(0)).dx,
      };
    }

    /// The device's own text size.
    ///
    /// iOS multiplies every point size by the Display > Text Size setting.
    /// The notches below the default are 0.941 / 0.882 / 0.824 (the iOS
    /// content-size categories, as a fraction of a 17pt body), and the ones
    /// above run to 1.235 before the accessibility sizes begin.
    ///
    /// 0.824 is the smallest, and it is what the calibration screenshots were
    /// taken at — which is why their hairlines read 14, 19 and 25 higher than
    /// a harness rendering at 1.0. Every FIXED size matched those screenshots
    /// to within half a point (emblem 126.3 against 126.8, strip 79.3 against
    /// 79.2, ring 56.0 against 55.5); only the text boxes were short, and all
    /// of them by the same factor. Type metrics cannot do that. A setting can.
    const double deviceTextScale = 0.824;

    testWidgets('at the calibration screenshots\' text size, the harness '
        'lands on the device', (tester) async {
      await compose(tester, textScale: deviceTextScale);

      // What the diagnosis rests on, and what a later change to the page
      // cannot move: every FIXED size matches the screenshots, and the one
      // text box measurable between two of them is short by the setting.
      //
      // The screenshots' own hairline positions are NOT asserted here. They
      // were read before the hero gaps became flexible, so the page has
      // legitimately moved since; what they proved is recorded in history.
      expect(
        tester.getSize(ringFinder(tester, 128)).height,
        closeTo(126.3, 0.6),
        reason: 'emblem',
      );
      expect(
        tester.getSize(find.byType(SondrPhoto).first).height,
        closeTo(79.3, 0.6),
        reason: 'photo strip tile',
      );
      expect(
        tester.getSize(ringFinder(tester, 56).first).height,
        closeTo(56.0, 0.6),
        reason: 'in-progress ring',
      );
      // 19.5 on the screenshots; 23.8 if the harness renders at 1.0. This is
      // the number that named the cause.
      expect(
        tester.getRect(find.text('In progress')).height,
        closeTo(19.5, 0.6),
      );
      expectNoOverflow(tester);
    });

    /// Every iOS text size, including the ones above the default.
    const sweep = [0.824, 0.882, 0.941, 1.0, 1.059, 1.118, 1.235];

    /// Where the figures started before the handle and its line became a
    /// pair, at the sizes where the pin still holds exactly. Pairing them
    /// moved air from between the two lines to either side of them, which is
    /// a change to the hero and must be no change at all to the page below.
    final statsTopBefore = <double, double>{
      0.824: 317.20,
      0.882: 313.70,
      0.941: 306.70,
      1.0: 300.70,
    };

    /// Readable things, top to bottom, as (name, finder) in page order.
    ///
    /// Overlap between any two of them is the failure this guards. It is the
    /// one that actually happened: the hero's box used to be a fixed height,
    /// so once its two gaps hit their 9 floor the subtitle had nowhere to go
    /// and painted 9.5 over the lifetime-hours figure at 1.235. Nothing was
    /// CLIPPED — a RenderFlex overflow paints through — which is why a test
    /// that only watched the tab-bar clearance stayed green over it.
    List<(String, Finder)> readable(WidgetTester tester) => [
      ('emblem', ringFinder(tester, 128)),
      ('handle', find.text('tanaka')),
      ('subtitle', find.textContaining('to your next milestone')),
      ('stat figure', find.text('76')),
      ('stat label', find.text('day streak')),
      ('Friends', find.text('Friends')),
      ('Milestones', find.text('Milestones')),
      ('photo strip', find.byType(SondrPhoto).first),
      ('In progress', find.text('In progress')),
      ('ring', ringFinder(tester, 56).first),
      ('ring label', find.text('Task 0')),
    ];

    /// Asserts the whole contract at one text size.
    Future<Map<String, double>> sweepOne(
      WidgetTester tester,
      double ts, {
      required bool withFriends,
    }) async {
      final m = await compose(tester, textScale: ts, withFriends: withFriends);

      // 1. Nothing overflowed. NOT swallowed with takeException: an overflow
      //    here is the bug, not noise to be tidied away.
      expectNoOverflow(tester);

      // 2. The pair is a pair: 4 between the handle and its line, at every
      //    size, and the flexible air is OUTSIDE the pair.
      expect(
        m['handleToSubline'],
        closeTo(4 * 0.9906, 0.5),
        reason: 'handle→subtitle @$ts',
      );
      // The two flexible gaps are equal, and neither goes under its floor —
      // which is the tier the gap below the pair was fixed at before it
      // could flex, so it never reads tighter than it used to.
      for (final k in ['emblemToHandle', 'sublineToStats']) {
        expect(
          m[k],
          greaterThanOrEqualTo(16 * 0.9906 - 0.01),
          reason: '$k is under its floor @$ts',
        );
      }
      expect(
        m['emblemToHandle'],
        closeTo(m['sublineToStats']!, 0.5),
        reason: 'the two flexible gaps parted company @$ts',
      );

      // 3. Nothing readable overlaps anything else readable.
      final items = readable(tester);
      for (var i = 0; i < items.length - 1; i++) {
        final (nameA, a) = items[i];
        final (nameB, b) = items[i + 1];
        expect(
          tester.getRect(a).bottom,
          lessThanOrEqualTo(tester.getRect(b).top + 0.01),
          reason: '"$nameA" overlaps "$nameB" at textScale $ts',
        );
      }

      // 4. The emblem never moves, whatever the text does.
      expect(m['emblemTop'], closeTo(92.6, 0.5), reason: 'emblem @$ts');

      // 5. The labels stay above the tab bar — up to 1.118.
      //
      // At 1.235 they sit 6 BEHIND it at rest, and that is the honest
      // outcome rather than a regression: at the largest text size iOS
      // offers the first screen needs more room than 844 leaves above the
      // tab bar, and something has to give. What gives now is the resting
      // position of a line on a page that scrolls — the labels are a swipe
      // away. What used to give was the subtitle, which painted over the
      // lifetime-hours figure and was illegible at every scroll position.
      //
      // Bounded, so it cannot quietly get worse.
      if (ts <= 1.118) {
        expect(m['clearance'], greaterThan(0), reason: 'clearance @$ts');
      } else {
        expect(m['clearance'], greaterThan(-10), reason: 'clearance @$ts');
      }

      if (ts <= 1.0) {
        // The pin holds exactly while the hero has slack to give.
        expect(
          m['labelCentre'],
          closeTo(m['homeCta']!, 0.5),
          reason: 'the pin let go at textScale $ts',
        );
        expect(m['emblemToHandle'], greaterThan(16 * 0.9906 + 0.01));
        // And the figures start exactly where they did before the pair was
        // paired: moving air from between the two lines to either side of
        // them is a change to the hero, not to the page under it.
        expect(
          m['statsTop'],
          closeTo(statsTopBefore[ts]!, 0.5),
          reason: 'the stats row moved @$ts',
        );
      } else {
        // Past that the hero is at its floor and YIELDS: the page gets
        // taller and the labels sit below Home's line, never above it.
        expect(
          m['labelCentre'],
          greaterThanOrEqualTo(m['homeCta']! - 0.5),
          reason: 'the labels rose above Home\'s line at textScale $ts',
        );
        expect(m['emblemToHandle'], closeTo(16 * 0.9906, 0.1));
      }
      // Never a void, either of them.
      expect(m['emblemToHandle'], lessThanOrEqualTo(32));
      expect(m['sublineToStats'], lessThanOrEqualTo(32));
      return m;
    }

    for (final ts in sweep) {
      testWidgets('at textScale $ts the page holds together', (tester) async {
        await sweepOne(tester, ts, withFriends: false);
      });
    }

    for (final ts in sweep) {
      testWidgets('at textScale $ts the page holds together WITH a friends '
          'row', (tester) async {
        await sweepOne(tester, ts, withFriends: true);
      });
    }

    /// Sparse pages: a guest, a brand-new account, a page with milestones and
    /// nothing running.
    ///
    /// The composition was signed off against a full page, and the void guard
    /// only ever ran against that fixture. On a guest's page — no handle, no
    /// tasks, no milestones — the same pinned height had a third less content
    /// to fill it, the two flexible gaps took the whole difference, and the
    /// device showed 117 points of nothing between the ring and the line
    /// under it.
    ///
    /// Each fixture is swept at the smallest, default and largest text sizes.
    /// Which text sizes each fixture can actually land the pin at.
    ///
    /// The pin is worth having only when the gaps it asks for are still gaps.
    /// A full page asks for 2 points each; a new account with two tasks and
    /// no milestone strip asks for 57, and the honest answer there is not to
    /// aim at Home's line at all. "data but no handle" is the interesting
    /// one — it wants more than the ceiling at the smallest text size and
    /// 31.7 at the default, so the same page pins at one size and not at the
    /// one below it.
    for (final (name, handle, taskCount, photoCount, pinsAt) in [
      ('full', 'tanaka', 6, 4, [0.824, 1.0, 1.235]),
      ('guest', '', 0, 0, <double>[]),
      ('new user', 'tanaka', 2, 0, <double>[]),
      ('milestones, nothing running', 'tanaka', 0, 4, <double>[]),
      ('data but no handle', '', 6, 4, [1.0, 1.235]),
    ]) {
      for (final ts in [0.824, 1.0, 1.235]) {
        testWidgets('$name at textScale $ts has no voids', (tester) async {
          tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
          tester.view.devicePixelRatio = 3.0;
          tester.view.padding = const FakeViewPadding(
            top: top13 * 3,
            bottom: 34 * 3,
          );
          addTearDown(tester.view.reset);
          await pumpProfile(
            tester,
            inShell: true,
            textScale: ts,
            tasks: [
              for (var i = 0; i < taskCount; i++)
                _task('Task $i', seconds: 45900),
            ],
            profile: handle.isEmpty
                ? null
                : Profile(uid: 'me', username: handle, displayName: 'T'),
            milestonePhotos: [
              for (var i = 0; i < photoCount; i++) _photo(1000 + i),
            ],
          );
          final scale = figmaScale(tester.element(find.byType(ProfileScreen)));

          // Nothing clipped, whatever the data.
          expectNoOverflow(tester);

          final hairlines = find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == 1,
          );
          // The figure is told from the label by its size, because WHICH
          // figures appear depends on the data.
          final statFigure = find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.style?.fontSize != null &&
                (w.style!.fontSize! - 22 * scale).abs() < 0.01,
          );

          // Page order, with whatever this fixture does not have left out.
          // The hairlines count as elements: a section break and the gap
          // under the line are two gaps, not one 37-point chasm.
          final elements = <(String, Finder)>[
            ('emblem', ringFinder(tester, 128)),
            if (handle.isNotEmpty) ('handle', find.text(handle)),
            (
              'subtitle',
              taskCount > 0
                  ? find.textContaining('to your next milestone')
                  : find.text('No task in progress.'),
            ),
            ('stat figure', statFigure.first),
            ('stat label', find.text('hours')),
            ('hairline 1', hairlines.at(0)),
            ('Friends', find.text('Friends')),
            ('hairline 2', hairlines.at(1)),
            ('Milestones', find.text('Milestones')),
            if (photoCount > 0) ('photo strip', find.byType(SondrPhoto).first),
            ('hairline 3', hairlines.at(2)),
            ('In progress', find.text('In progress')),
            if (taskCount > 0) ...[
              ('ring', ringFinder(tester, 56).first),
              ('ring label', find.text('Task 0')),
            ] else
              ('empty line', find.textContaining('Start a task')),
          ];

          // THE RUNTIME VOID GUARD. Every gap the page actually renders, on
          // this data, at this text size — not the handful the full fixture
          // happens to produce. The bottom clearance is excluded: space
          // above the tab bar is the end of the page, not a gap in it.
          for (var i = 0; i < elements.length - 1; i++) {
            final (nameA, a) = elements[i];
            final (nameB, b) = elements[i + 1];
            final gap =
                tester.getRect(b).top - tester.getRect(a).bottom;
            expect(
              gap,
              greaterThan(-0.01),
              reason: '"$nameA" overlaps "$nameB" ($name, $ts)',
            );
            expect(
              gap,
              lessThanOrEqualTo(32 * scale + 0.01),
              reason: 'a void of $gap between "$nameA" and "$nameB" '
                  '($name, $ts)',
            );
          }

          // The two hero gaps stay equal to each other, whatever they are.
          final emblemBottom = tester.getRect(ringFinder(tester, 128)).bottom;
          final capTop = handle.isNotEmpty
              ? tester.getRect(find.text(handle)).top
              : tester.getRect(elements[1].$2).top;
          final capBottom = tester.getRect(elements[handle.isEmpty ? 1 : 2].$2).bottom;
          final gapA = capTop - emblemBottom;
          final gapB = tester.getRect(statFigure.first).top - capBottom;
          expect(gapA, closeTo(gapB, 0.5), reason: 'hero gaps ($name, $ts)');
          // With no ring row the gaps are FIXED, not stretched to their
          // ceiling: nothing below asks the hero to reach, so it does not.
          // Without this the cap alone hides the difference — a pinned
          // guest page caps at 32 and passes every other check here.
          if (!pinsAt.contains(ts)) {
            // Unpinned: a fixed 18 either side of the pair, and the slack at
            // the foot. Nothing below is asking the hero to reach.
            expect(
              gapA,
              closeTo(18 * scale, 0.5),
              reason: 'unpinned hero gaps ($name, $ts)',
            );
          } else {
            expect(gapA, greaterThanOrEqualTo(16 * scale - 0.01));
            expect(gapA, lessThanOrEqualTo(32 * scale + 0.01));
          }

          // The emblem never moves, on any data.
          expect(
            tester.getRect(ringFinder(tester, 128)).top,
            closeTo(92.6, 0.5),
            reason: 'emblem ($name, $ts)',
          );
          // And the account block is still past the bottom edge.
          expect(
            tester.getTopLeft(find.byType(AccountBody)).dy,
            greaterThanOrEqualTo(tabBarTop13),
            reason: 'account block ($name, $ts)',
          );

          // Where it pins, it pins exactly. Where it does not — no ring row,
          // or a pin that would need more than the ceiling — the labels are
          // simply higher up a shorter page.
          if (taskCount > 0) {
            final labelCentre = tester.getRect(find.text('Task 0')).center.dy;
            final cta = homeCtaCentreY(
              tester.element(find.byType(ProfileScreen)),
            );
            if (!pinsAt.contains(ts)) {
              // Unpinned, so the labels sit ABOVE Home's line — the page is
              // shorter. Never below it, which would mean the slack had gone
              // somewhere between the sections.
              expect(
                labelCentre,
                lessThan(cta - 0.5),
                reason: 'unpinned but on the line anyway ($name, $ts)',
              );
            } else if (ts <= 1.0) {
              expect(
                labelCentre,
                closeTo(cta, 0.5),
                reason: 'the pin let go ($name, $ts)',
              );
            } else {
              // Big text: pinned, but the content needs more room than the
              // target, so it yields downward rather than overflowing.
              expect(
                labelCentre,
                greaterThanOrEqualTo(cta - 0.5),
                reason: 'the labels rose above the line ($name, $ts)',
              );
            }
          }
        });
      }
    }

    testWidgets('nothing in the first screen refuses to be measured', (
      tester,
    ) async {
      // IntrinsicHeight asks the subtree for its intrinsic height, and a
      // RenderViewport — ListView, CustomScrollView, a GridView — throws
      // rather than answer. So do LayoutBuilder and anything else that can
      // only size itself against real constraints. The two strips are
      // SingleChildScrollView + Row precisely because that render object
      // DELEGATES intrinsics to its child; swap either for a ListView and
      // the page stops laying out at all.
      for (final ts in [1.0, 1.235]) {
        await compose(tester, textScale: ts);
        expectNoOverflow(tester);
        // The strips are still the shape that can answer.
        final strips = find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        );
        expect(strips, findsNWidgets(2));
        for (final element in strips.evaluate()) {
          expect(
            (element.widget as SingleChildScrollView).child,
            isA<Row>(),
            reason: 'a strip stopped being a Row',
          );
        }
        // And nothing that cannot. Scoped to the page rather than to the
        // widget that does the measuring, which is private to the screen —
        // and which is why these are stated as "nowhere on this page".
        for (final (what, finder) in [
          ('ListView', find.byType(ListView)),
          ('CustomScrollView', find.byType(CustomScrollView)),
          ('GridView', find.byType(GridView)),
        ]) {
          expect(
            find.descendant(of: find.byType(ProfileScreen), matching: finder),
            findsNothing,
            reason: '$what cannot answer an intrinsic query',
          );
        }
        // Exactly one LayoutBuilder: the page's own, which reads the scroll
        // viewport and sits ABOVE the measured column. A second one would be
        // inside it, and a LayoutBuilder cannot be measured either.
        expect(
          find.descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(LayoutBuilder),
          ),
          findsOneWidget,
        );
      }
    });

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
      // Top inset 47 plus the 46 top margin, scaled: no text sits above the
      // emblem, so this is the one number on the page that type cannot move.
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
        expect(m[k], closeTo(14, 2), reason: k);
      }
      // And still tighter than every gap BELOW a heading, the tightest of
      // which is the 20 to the rings — so a heading belongs to its content.
      for (final k in ['hl1ToFriends', 'hl2ToMilestones', 'hl3ToInProgress']) {
        expect(m[k], lessThan(m['inProgressToRings']!), reason: k);
      }
      expect(m['milestonesToPhotos'], closeTo(26, 3));
      expect(m['inProgressToRings'], closeTo(20, 3));
      expectNoOverflow(tester);
    });

    testWidgets('the handle and its line have air either side of the PAIR, '
        'never between them', (tester) async {
      final m = await compose(tester);
      // 4 between the two lines — tighter than any other number on the page,
      // which is what makes them read as one thing.
      expect(m['handleToSubline'], closeTo(4 * 0.9906, 0.5));
      // And the air is outside: equal above the handle and below the line,
      // whatever the pin leaves over, floored at 16.
      expect(
        (m['emblemToHandle']! - m['sublineToStats']!).abs(),
        lessThanOrEqualTo(0.5),
      );
      for (final k in ['emblemToHandle', 'sublineToStats']) {
        expect(m[k], greaterThanOrEqualTo(16 * 0.9906 - 0.01), reason: k);
      }
      // The pair gap is the tightest of the three by a long way.
      expect(m['handleToSubline'], lessThan(m['emblemToHandle']! / 2));
      expectNoOverflow(tester);
    });

    /// The two horizontal scrollers, told apart by what they contain.
    Finder scrollerAround(Finder item) => find.ancestor(
      of: item,
      matching: find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );

    testWidgets('both strips bleed to the screen edge, margin as padding', (
      tester,
    ) async {
      // Five of each, so there is something past the fourth to peek.
      tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(
        top: top13 * 3,
        bottom: 34 * 3,
      );
      addTearDown(tester.view.reset);
      await pumpProfile(
        tester,
        inShell: true,
        tasks: [for (var i = 0; i < 5; i++) _task('Task $i', seconds: 45900)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
        milestonePhotos: [for (var i = 0; i < 5; i++) _photo(1000 + i)],
      );
      final scale = figmaScale(tester.element(find.byType(ProfileScreen)));
      final margin = 24 * scale;

      final photos = find.byType(SondrPhoto);
      final rings = ringFinder(tester, 56);
      expect(photos, findsNWidgets(5));
      expect(rings, findsNWidgets(5));

      // Both viewports span the whole screen.
      for (final strip in [scrollerAround(photos.first), scrollerAround(rings.first)]) {
        expect(tester.getTopLeft(strip).dx, closeTo(0, 0.5));
        expect(tester.getBottomRight(strip).dx, closeTo(w13, 0.5));
      }

      // The first item of each still starts on the content margin.
      expect(tester.getTopLeft(photos.first).dx, closeTo(margin, 0.5));
      expect(
        tester.getTopLeft(ringFinder(tester, 56).first).dx -
            (ringTile * scale - 56 * scale) / 2,
        closeTo(margin, 0.5),
      );

      // The fifth photo shows past the screen edge by enough to read as more.
      final fifthPhotoLeft = tester.getTopLeft(photos.at(4)).dx;
      expect(w13 - fifthPhotoLeft, greaterThanOrEqualTo(14));

      // The fourth ring is not clipped, and the fifth peeks by as much as
      // the fifth photo does — the tile width is what tunes that.
      expect(tester.getBottomRight(rings.at(3)).dx, lessThanOrEqualTo(w13));
      expect(w13 - tester.getTopLeft(rings.at(4)).dx, greaterThanOrEqualTo(15));

      // And the fourth task's NAME is whole too — the label is the widest
      // part of a tile, so it clips before the ring does.
      expect(
        tester.getBottomRight(find.text('Task 3')).dx,
        lessThanOrEqualTo(w13),
      );
      expectNoOverflow(tester);
    });

    testWidgets('the headings stay inside the content box', (tester) async {
      // Only the strips bleed. A heading on the screen edge would read as a
      // different page.
      final m = await compose(tester);
      expect(m['friendsLeft'], closeTo(24, 0.5));
      expect(m['milestonesLeft'], closeTo(24, 0.5));
      expect(m['inProgressLeft'], closeTo(24, 0.5));
      expect(m['hairlineLeft'], closeTo(24, 0.5));
      expectNoOverflow(tester);
    });

    testWidgets('5. VOID GUARD: no gap between sections exceeds 32', (
      tester,
    ) async {
      final m = await compose(tester);
      // Everything from the stats row down to the rings. The top margin and
      // the bottom clearance are margins, not gaps, so they are excluded.
      const gaps = [
        // The two flexible ones first: they are the only gaps on the page
        // that a change elsewhere can inflate.
        'emblemToHandle',
        'handleToSubline',
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
      // The upper bound was relaxed to 756 — a clearance floor of 14 — when
      // the harness was measuring the test font's wrapped stat labels. With
      // Inter the page is 17 shorter and lands at 736, back inside the
      // original 22-to-38 window, so the bound is the window again.
      expect(m['ringsBottom'], inInclusiveRange(tabBarTop13 - 38, 748));
      expect(m['clearance'], greaterThanOrEqualTo(22));
      expectNoOverflow(tester);
    });

    testWidgets("8. the ring labels sit on Home's \"View your progress\" line", (
      tester,
    ) async {
      final m = await compose(tester);
      // The whole point: the two bottom lines of the app are one line.
      expect(m['labelCentre'], closeTo(m['homeCta']!, 0.5));
      // Not a copied constant — Home's own numbers, read through
      // homeCtaCentreY, which is also what Home lays itself out with.
      expect(m['homeCta'], closeTo(734.35, 1));
      // The emblem did not move to pay for it.
      expect(m['emblemTop'], closeTo(92.6, 0.5));
      // The two flexible gaps took the difference, equally, and neither is
      // anywhere near a void. If either exceeds 32 the pin is asking for
      // more than the hero should give.
      expect(m['emblemToHandle'], closeTo(m['sublineToStats']!, 0.5));
      for (final k in ['emblemToHandle', 'sublineToStats']) {
        expect(m[k], greaterThanOrEqualTo(16 * 0.9906 - 0.01), reason: k);
        expect(m[k], lessThanOrEqualTo(32), reason: k);
      }
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

    testWidgets('the free space never lands inside the pair', (
      tester,
    ) async {
      // It used to be the whole hero that had to stay tight while the
      // sections took the slack. Now the slack is deliberately part of the
      // hero — above the handle and below its line — and the thing that must
      // stay tight is the PAIR.
      useReferenceViewport(tester);
      await pumpProfile(
        tester,
        inShell: true,
        tasks: [_task('Spanish', seconds: 45900)],
        profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
      );
      // Between the two lines of the pair.
      final pair =
          tester.getTopLeft(find.textContaining('to your next milestone')).dy -
          tester.getBottomLeft(find.text('tanaka')).dy;
      // And the flexible gap under the pair, which is where the slack goes.
      // 45900s is 12.75 lifetime hours, so the first figure reads 12: the
      // figure floors. (It read 13 until the rounding was fixed.)
      final flexible =
          tester.getTopLeft(find.text('12')).dy -
          tester
              .getBottomLeft(find.textContaining('to your next milestone'))
              .dy;

      // The section break below it — the widest gap the composition allows
      // anywhere on the page.
      final lines = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 1,
      );
      final sectionBreak =
          tester.getTopLeft(lines.first).dy -
          tester.getBottomLeft(find.text('day streak')).dy;

      // The pair stays at its 4 while everything around it absorbs — tighter
      // than the section break, and a fraction of the gap below it.
      expect(pair, closeTo(4, 0.5));
      expect(pair, lessThan(sectionBreak));
      expect(pair, lessThan(flexible / 4));
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

    group('the scroll end', () {
      /// The account block's last line is one word now — More — and what sits
      /// under it is the tab bar. The clearance is the word's own 12 of tap
      /// padding plus the block's declared 12: the same 24 the terms line had
      /// under it before the word was added.
      for (final ts in [0.824, 1.0, 1.235]) {
        testWidgets('a guest: 24 under the last line at $ts', (tester) async {
          useReferenceViewport(tester);
          await pumpProfile(
            tester,
            tasks: [_task('Spanish', seconds: 3600)],
            profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
            inShell: true,
            textScale: ts,
          );
          // All the way to the end.
          await tester.drag(find.byType(ProfileScreen), const Offset(0, -2000));
          await tester.pumpAndSettle();

          final word = tester.getRect(find.text('More'));
          final block = tester.getRect(find.byType(AccountBody));
          expect(
            block.bottom - word.bottom,
            closeTo(24, 1),
            reason: 'the clearance under the last line changed',
          );
          // And the end of the content is the end of the body: nothing of the
          // block is left under the tab bar.
          expect(block.bottom, lessThanOrEqualTo(refBodyHeight() + 0.5));
          expectNoOverflow(tester);
        });

        testWidgets('signed in: the same 24 at $ts', (tester) async {
          useReferenceViewport(tester);
          await pumpProfile(
            tester,
            tasks: [_task('Spanish', seconds: 3600)],
            profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
            inShell: true,
            textScale: ts,
            account: _Account(),
          );
          await tester.drag(find.byType(ProfileScreen), const Offset(0, -2000));
          await tester.pumpAndSettle();

          expect(find.text('Signed in'), findsOneWidget);
          final word = tester.getRect(find.text('More'));
          final block = tester.getRect(find.byType(AccountBody));
          expect(block.bottom - word.bottom, closeTo(24, 1));
          expect(block.bottom, lessThanOrEqualTo(refBodyHeight() + 0.5));
          expectNoOverflow(tester);
        });
      }

      testWidgets('the page is still longer than one screen', (tester) async {
        useReferenceViewport(tester);
        await pumpProfile(
          tester,
          tasks: [_task('Spanish', seconds: 3600)],
          profile: const Profile(uid: 'me', username: 'tanaka', displayName: 'T'),
          inShell: true,
        );
        // At rest the block is below the fold, as it has always been — the
        // word replacing a row of five did not shorten the page into it.
        expect(
          tester.getTopLeft(find.byType(AccountBody)).dy,
          greaterThanOrEqualTo(refBodyHeight()),
        );
      });
    });
  });

}

/// Signed in, for the account block's signed-in face.
class _Auth implements AuthRepository {
  _Auth(this.user);

  final User? user;

  @override
  User? get currentUser => user;

  @override
  bool get isAnonymous => user?.isAnonymous ?? true;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Account implements User {
  @override
  bool get isAnonymous => false;

  @override
  String? get email => 'tanaka@example.com';

  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
