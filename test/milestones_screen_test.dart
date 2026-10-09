import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/features/photos/milestones_screen.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/photos/widgets/collage_grid.dart';
import 'package:sondr/shared/ring/ring_dial.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';
import 'package:sondr/shared/sondr_header.dart';

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
    expect(find.text('20 hours · no photos'), findsOneWidget);
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
    expect(dial.outerStroke, closeTo(3 * scale, 0.001));
    expect(dial.outerStroke, closeTo(thinRingStroke(dial.size), 0.001));
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
  const _Harness({this.startOnPhotos = false});

  final bool startOnPhotos;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark(),
    home: MilestonesScreen(startOnPhotos: startOnPhotos),
  );
}
