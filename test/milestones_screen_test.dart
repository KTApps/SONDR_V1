import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Source;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/features/photos/milestones_screen.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/models/collage.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/photos/photo_refresh.dart';
import 'package:sondr/features/photos/photo_viewer.dart';
import 'package:sondr/features/photos/collage_selection.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/photos/widgets/collage_grid.dart';
import 'package:sondr/shared/ring/ring_dial.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';
import 'package:sondr/shared/sondr_header.dart';

import 'tiny_png.dart';

/// The lens toggle is the only state this screen owns, so the thing worth
/// asserting is that it actually swaps what is on screen.
///
/// With no backend behind the test the local seed supplies the tasks (Golf has
/// just passed 20h, so it is the one task with a milestone) and the photo store
/// is empty — which makes both lenses unambiguous: a task row under one, the
/// quiet empty line under the other.
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: _Harness()));
    await tester.pumpAndSettle();
  }

  // The page has no title any more, so the only "Milestones" is the tab.
  Finder milestonesLens() => find.text('Milestones');

  testWidgets('opens on the Milestones lens', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Golf'), findsOneWidget);
    // The task's OWN milestone count, not the hours the ring already states.
    expect(find.text('1 milestone · no photos'), findsOneWidget);
    expect(find.text('No photos yet.'), findsNothing);
  });

  testWidgets('Photos swaps the lens, and Milestones swaps it back', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('No photos yet.'), findsOneWidget);
    expect(find.text('Golf'), findsNothing);

    await tester.tap(milestonesLens());
    await tester.pumpAndSettle();
    expect(find.text('Golf'), findsOneWidget);
    expect(find.text('No photos yet.'), findsNothing);
  });

  testWidgets('both lens names stay on screen under either lens', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Milestones'), findsOneWidget);

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Milestones'), findsOneWidget);
  });

  _galleryTests();
  _journeyGridTests();

  testWidgets('the page opens on the tabs, with no title above them', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(SondrHeader), findsNothing);
  });

  testWidgets('each tab is centred in its own half of the screen', (
    tester,
  ) async {
    await pumpScreen(tester);
    // Measured, not reasoned about: the halves are of the FULL width, so the
    // two centres land on the screen's quarter points.
    final width = tester.getSize(find.byType(MilestonesScreen)).width;
    expect(
      tester.getCenter(find.text('Milestones')).dx,
      moreOrLessEquals(width / 4, epsilon: 0.5),
    );
    expect(
      tester.getCenter(find.text('Photos')).dx,
      moreOrLessEquals(width * 3 / 4, epsilon: 0.5),
    );
  });

  testWidgets('a completed ring is Ø56 at the same thin weight', (
    tester,
  ) async {
    // One thickness across the app: the done rings here and the profile's
    // progress rings are the same weight, so a ring reads as a ring whichever
    // screen it is standing on.
    await pumpScreen(tester);
    final finder = find.byType(RingDial).first;
    final scale = figmaScale(tester.element(finder));
    final dial = tester.widget<RingDial>(finder);

    expect(dial.size, closeTo(56 * scale, 0.001));
    expect(dial.outerStroke, closeTo(ringStroke(scale), 0.001));
    expect(dial.outerStroke, closeTo(7 * scale, 0.001));
  });

  testWidgets('a task journey has no title, and names the task per band', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Golf'));
    await tester.pumpAndSettle();

    // We are on the journey: Golf is just past 20h, so it has one band, and
    // with no photo store behind the test that band is empty.
    expect(find.text('No photos from this stretch.'), findsOneWidget);
    // No title, in either of its old forms.
    expect(find.byType(SondrHeader), findsNothing);
    expect(find.text('Golf · 20 hours'), findsNothing);
    // The band row names the TASK now; the ring already says "20h".
    expect(find.text('20 hours'), findsNothing);
    expect(find.text('20h'), findsWidgets);
    // Still dismissable.
    expect(find.text('Back'), findsWidgets);
  });

  testWidgets('a caller can land straight on one milestone', (tester) async {
    // The Profile strip does this: the page opens and continues at once into
    // the task's journey, on the stretch that was tapped — the same two
    // pushes a tap on the row and then the band would make.
    const golf = Task(
      id: 'golf',
      name: 'Golf',
      secondsByDay: {'2026-10-01': 20 * 3600 + 60},
    );
    await tester.pumpWidget(const ProviderScope(
      child: _Harness(landOnTask: golf, landOnBandHours: 20),
    ));
    await tester.pumpAndSettle();

    // On the journey, not the list: the stretch is shown (empty, with no
    // photo store behind the test) and the lens toggle is behind us.
    expect(find.text('No photos from this stretch.'), findsOneWidget);
    expect(find.text('Photos'), findsNothing);
    expect(find.text('20h'), findsWidgets);

    // Back unwinds to the page itself, on its default lens.
    await tester.tap(find.text('Back').last);
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('No photos from this stretch.'), findsNothing);
  });

  testWidgets('a stretch with a stored collage still shows its crossing photo', (
    tester,
  ) async {
    // The collage was composed at the crossing, before the crossing photo
    // was captured. Stored: two seeded photos. The band: those two and the
    // crossing photo. The detail shows all three.
    const golf = Task(id: 'golf', name: 'Golf', secondsByDay: {'2026-10-01': 20 * 3600 + 60});
    Photo photo(int ts, {int? hours}) => Photo(
          taskId: 'golf', taskName: 'Golf', dayKey: '2026-10-01', timestamp: ts,
          sessionSeconds: 60, photoUrl: '', storagePath: '',
          milestoneHours: hours, cumulativeSeconds: hours == null ? ts : 20 * 3600 + 5,
        );
    final seeded = [photo(1000), photo(5000)];
    final crossing = photo(99, hours: 20);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        collagesListProvider.overrideWith((ref) async => [
              Collage(taskId: 'golf', milestoneHours: 20, photoIds: [for (final p in seeded) p.id], edited: false),
            ]),
        collagePhotosProvider.overrideWith((ref, key) async => seeded),
        bandPhotosProvider.overrideWith((ref, key) async => [...seeded, crossing]),
      ],
      child: const _Harness(landOnTask: golf, landOnBandHours: 20),
    ));
    await tester.pumpAndSettle();

    final grid = tester.widget<CollageGrid>(find.byType(CollageGrid).first);
    expect(grid.photos.map((p) => p.id), [seeded[0].id, seeded[1].id, crossing.id]);
  });

  testWidgets('a tile in the stretch opens the viewer on that photo, the stretch a swipe away', (
    tester,
  ) async {
    final factoryBefore = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = factoryBefore);
    const golf = Task(id: 'golf', name: 'Golf', secondsByDay: {'2026-10-01': 20 * 3600 + 60});
    Photo photo(int ts, {int? hours}) => Photo(
          taskId: 'golf', taskName: 'Golf', dayKey: '2026-10-01', timestamp: ts,
          sessionSeconds: 60, photoUrl: '', storagePath: '',
          milestoneHours: hours, cumulativeSeconds: hours == null ? ts : 20 * 3600 + 5,
        );
    // The collage shows two of the band's four; the viewer reaches all four.
    final seeded = [photo(1000), photo(5000)];
    final band = [photo(500), ...seeded, photo(9000)];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        collagesListProvider.overrideWith((ref) async => [
              Collage(taskId: 'golf', milestoneHours: 20, photoIds: [for (final p in seeded) p.id], edited: true),
            ]),
        collagePhotosProvider.overrideWith((ref, key) async => seeded),
        bandPhotosProvider.overrideWith((ref, key) async => band),
      ],
      child: const _Harness(landOnTask: golf, landOnBandHours: 20),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);

    // The second tile: the collage's second photo, page 2 of the four.
    await tester.tap(find.descendant(of: find.byType(CollageGrid), matching: find.byType(SondrPhoto)).at(1));
    await tester.pumpAndSettle();
    final viewer = tester.widget<PhotoViewer>(find.byType(PhotoViewer));
    expect(viewer.photos.map((p) => p.timestamp), [1000, 5000, 500, 9000]);
    expect(viewer.index, 1);
    expect(find.text('2 of 4'), findsOneWidget);
  });

  testWidgets('a row whose photo count is still loading says nothing about photos', (
    tester,
  ) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        taskBandPhotosProvider.overrideWith((ref, id) => Completer<List<Photo>>().future),
      ],
      child: const _Harness(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Golf'), findsOneWidget);
    expect(find.text('1 milestone'), findsOneWidget);
    expect(find.textContaining('photo'), findsNothing);
  });

  testWidgets('a stretch whose data is still loading shows neither the line nor a grid', (
    tester,
  ) async {
    const golf = Task(id: 'golf', name: 'Golf', secondsByDay: {'2026-10-01': 20 * 3600 + 60});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        collagesListProvider.overrideWith((ref) => Completer<List<Collage>>().future),
      ],
      child: const _Harness(landOnTask: golf, landOnBandHours: 20),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('20h'), findsWidgets);
    expect(find.text('No photos from this stretch.'), findsNothing);
    expect(find.byType(CollageGrid), findsNothing);
  });

  test('the band photos are kept once nobody is listening', () async {
    // The last listener goes away — as it does when the detail is popped —
    // and the provider is NOT disposed: the next read is the same answer,
    // with no second fetch. Without keepAlive it would be re-created, and
    // the first frame after re-opening would be empty again.
    final photos = _CountingPhotos();
    final container = ProviderContainer(
      overrides: [photosRepositoryProvider.overrideWithValue(photos)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(bandPhotosProvider('t|20'), (_, _) {});
    expect((await container.read(bandPhotosProvider('t|20').future)).length, 1);
    expect(photos.forTaskCalls, 1);

    sub.close();
    await container.pump(); // let any disposal happen

    expect(container.read(bandPhotosProvider('t|20')).hasValue, isTrue);
    expect(photos.forTaskCalls, 1, reason: 'kept, so not fetched again');
  });

  testWidgets('invalidatePhotoViews re-reads the kept band photos', (tester) async {
    final photos = _CountingPhotos();
    late WidgetRef outerRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [photosRepositoryProvider.overrideWithValue(photos)],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          outerRef = ref;
          final v = ref.watch(bandPhotosProvider('t|20'));
          return Text(v.hasValue ? 'loaded ${v.value!.length}' : 'loading');
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('loaded 1'), findsOneWidget);
    expect(photos.forTaskCalls, 1);

    // A write tells every surface, and only then is it read again.
    invalidatePhotoViews(outerRef);
    await tester.pumpAndSettle();
    expect(photos.forTaskCalls, 2);
    expect(find.text('loaded 1'), findsOneWidget);
  });

  testWidgets('the grid is built once, with the crossing photo already in it', (
    tester,
  ) async {
    // The collage list, the collage's photos and the band resolve at three
    // different moments. Whatever frame first shows a grid must already
    // show all three photos — never a two-photo grid that regrows.
    const golf = Task(id: 'golf', name: 'Golf', secondsByDay: {'2026-10-01': 20 * 3600 + 60});
    Photo photo(int ts, {int? hours}) => Photo(
          taskId: 'golf', taskName: 'Golf', dayKey: '2026-10-01', timestamp: ts,
          sessionSeconds: 60, photoUrl: '', storagePath: '',
          milestoneHours: hours, cumulativeSeconds: hours == null ? ts : 20 * 3600 + 5,
        );
    final seeded = [photo(1000), photo(5000)];
    final crossing = photo(99, hours: 20);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        collagesListProvider.overrideWith((ref) => Future.delayed(const Duration(milliseconds: 20), () => [
              Collage(taskId: 'golf', milestoneHours: 20, photoIds: [for (final p in seeded) p.id], edited: false),
            ])),
        collagePhotosProvider.overrideWith((ref, key) => Future.delayed(const Duration(milliseconds: 40), () => seeded)),
        bandPhotosProvider.overrideWith((ref, key) => Future.delayed(const Duration(milliseconds: 120), () => [...seeded, crossing])),
      ],
      child: const _Harness(landOnTask: golf, landOnBandHours: 20),
    ));
    final seen = <int>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final grids = find.byType(CollageGrid);
      if (grids.evaluate().isNotEmpty) {
        seen.add(tester.widget<CollageGrid>(grids.first).photos.length);
      }
    }
    expect(seen, isNotEmpty);
    expect(seen.toSet(), {3}, reason: 'every frame that had a grid had the full three');
    expect(find.text('No photos from this stretch.'), findsNothing);
  });

  testWidgets('handed its stretch, the detail is built on the first frame', (
    tester,
  ) async {
    const golf = Task(id: 'golf', name: 'Golf', secondsByDay: {'2026-10-01': 20 * 3600 + 60});
    Photo photo(int ts) => Photo(
          taskId: 'golf', taskName: 'Golf', dayKey: '2026-10-01', timestamp: ts,
          sessionSeconds: 60, photoUrl: '', storagePath: '', cumulativeSeconds: ts,
        );
    final handed = BandDetail(collage: null, photos: [photo(1), photo(2), photo(3)]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Nothing underneath ever answers.
        bandDetailProvider.overrideWith((ref, key) => Completer<BandDetail>().future),
      ],
      child: _Harness(landOnTask: golf, landOnBandHours: 20, landOnDetail: handed),
    ));
    await tester.pump();            // the page
    await tester.pump();            // the post-frame push of the journey
    await tester.pump();            // the journey's first frame

    expect(tester.widget<CollageGrid>(find.byType(CollageGrid).first).photos.length, 3);
  });

  testWidgets('a caller can open straight onto the Photos lens', (
    tester,
  ) async {
    // The Profile doorway does this when it is counting captures rather than
    // milestones: landing on an empty Milestones lens would be a dead end.
    await tester.pumpWidget(
      const ProviderScope(child: _Harness(startOnPhotos: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No photos yet.'), findsOneWidget);
    expect(find.text('Golf'), findsNothing);
  });

  testWidgets('leaving is the same Back under either lens', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Back'), findsOneWidget);
  });
}

Photo _photo(String dayKey, int micros, {int? sharedAt}) => Photo(
  taskId: 'task_2',
  taskName: 'Golf',
  dayKey: dayKey,
  timestamp: micros,
  sessionSeconds: 1800,
  photoUrl: 'https://example.invalid/$micros.jpg',
  storagePath: 'users/me/photos/$micros.jpg',
  sharedAt: sharedAt,
);

/// The gallery itself, with a month store standing in for Firestore: does it
/// label the month, lay out every photo, and leave photo-less months out?
///
/// The stand-in photos carry no `cumulativeSeconds`, which is deliberate —
/// those are exactly the photos no 20h band can place, so the Milestones lens
/// cannot show them. Seeing all five here is the whole reason this lens exists.
void _galleryTests() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month);
  final older = DateTime(now.year, now.month - 2);
  final day = DayKey.of(DateTime(now.year, now.month, 1));

  Future<void> pumpGallery(
    WidgetTester tester,
    int count, {
    bool shareFirst = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The first photo is two months back, so the gallery offers three
          // months — but only the current one holds anything.
          earliestPhotoMonthProvider.overrideWith((ref) async => older),
          photosForMonthProvider.overrideWith((ref, monthKey) async {
            if (monthKey != DayKey.monthPrefix(thisMonth)) return const {};
            return {
              // The first one has been posted to the feed; the rest have not.
              day: [
                for (var i = 0; i < count; i++)
                  _photo(
                    day,
                    1000 + i,
                    sharedAt: shareFirst && i == 0 ? 1759999999 : null,
                  ),
              ],
            };
          }),
        ],
        child: const _Harness(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
  }

  testWidgets('labels the month and lays out every photo', (tester) async {
    await pumpGallery(tester, 5);
    expect(
      find.text('${DayKey.monthName(thisMonth.month)} ${thisMonth.year}'),
      findsOneWidget,
    );
    expect(find.byType(SondrPhoto), findsNWidgets(5));
    expect(find.text('No photos yet.'), findsNothing);
  });

  testWidgets('a tile opens the viewer on it, the month in its order a swipe away', (
    tester,
  ) async {
    final factoryBefore = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = factoryBefore);
    await pumpGallery(tester, 5);
    final tiles = find.byType(SondrPhoto);
    final shown = [
      for (var i = 0; i < 5; i++) tester.widget<SondrPhoto>(tiles.at(i)).url,
    ];
    await tester.tap(tiles.at(2));
    await tester.pumpAndSettle();
    final viewer = tester.widget<PhotoViewer>(find.byType(PhotoViewer));
    expect(viewer.photos.map((p) => p.photoUrl), shown);
    expect(viewer.index, 2);
    expect(find.text('3 of 5'), findsOneWidget);
  });

  testWidgets('only the shared photo is tagged', (tester) async {
    await pumpGallery(tester, 5);
    expect(find.text('Shared'), findsOneWidget);
  });

  testWidgets('nothing is tagged when nothing has been shared', (tester) async {
    await pumpGallery(tester, 1, shareFirst: false);
    expect(find.byType(SondrPhoto), findsOneWidget);
    expect(find.text('Shared'), findsNothing);
  });

  testWidgets('a month with nothing in it gets no heading', (tester) async {
    await pumpGallery(tester, 5);
    expect(
      find.text('${DayKey.monthName(older.month)} ${older.year}'),
      findsNothing,
    );
  });
}

/// The journey's grid is the collage grid, so the tag has to work there too —
/// and it is the one that also carries the curation editor's ×, which is why
/// the tag sits in the opposite corner.
void _journeyGridTests() {
  testWidgets('the collage grid tags only the photos that were shared', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CollageGrid(
            photos: [
              _photo('2026-10-01', 1, sharedAt: 1759999999),
              _photo('2026-10-01', 2),
              _photo('2026-10-01', 3),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CollageGrid), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({
    this.startOnPhotos = false,
    this.landOnTask,
    this.landOnBandHours,
    this.landOnDetail,
  });

  final bool startOnPhotos;
  final Task? landOnTask;
  final int? landOnBandHours;
  final BandDetail? landOnDetail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark(),
    home: MilestonesScreen(
      startOnPhotos: startOnPhotos,
      landOnTask: landOnTask,
      landOnBandHours: landOnBandHours,
      landOnDetail: landOnDetail,
    ),
  );
}

/// A photo store that counts its reads. Everything the providers under test
/// do not touch falls through to noSuchMethod.
class _CountingPhotos implements PhotosRepository {
  /// Reads answered from the cache — the ones a cold open pays for. Local-first
  /// also asks the server once behind every cached answer; that is counted
  /// apart, so "fetched again" means a second cache read, not the follow-up.
  int forTaskCalls = 0;
  int serverCalls = 0;
  static const Photo _one = Photo(
    taskId: 't', taskName: 'T', dayKey: '2026-10-01', timestamp: 7,
    sessionSeconds: 60, photoUrl: '', storagePath: '', cumulativeSeconds: 100,
  );

  @override
  Future<List<Photo>> photosForTask(String taskId) async {
    forTaskCalls++;
    return [_one];
  }

  @override
  Future<List<Photo>> photosForTaskFrom(String taskId, {Source source = Source.serverAndCache}) async {
    if (source == Source.server) {
      serverCalls++;
      return [_one];
    }
    return photosForTask(taskId);
  }

  @override
  Future<List<Photo>> photosForBand(String taskId, int milestoneHours) async =>
      bandPhotos(await photosForTask(taskId), milestoneHours);

  @override
  Future<List<Photo>> photosForBandFrom(String taskId, int milestoneHours, {Source source = Source.serverAndCache}) async =>
      bandPhotos(await photosForTaskFrom(taskId, source: source), milestoneHours);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
