import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/habits/models/daily_habits.dart';
import 'package:sondr/features/history/day_detail_sheet.dart';
import 'package:sondr/features/history/day_ring.dart';
import 'package:sondr/features/history/history_providers.dart';
import 'package:sondr/features/photos/delete_photo.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photo_viewer.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/features/profile/profile_metrics.dart';
import 'package:sondr/shared/blur_sheet.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

import 'tiny_png.dart';

/// The day sheet, redesigned: a header that stays, a row of photos that
/// says which task it is looking at, the tasks under it, and the habits.
void main() {
  // The 13 Pro: 390 × 844, the sheet's ceiling at 75% → its top at 211.
  const w = 390.0, h = 844.0, bottomInset = 34.0;
  const day = '2026-10-01'; // a Thursday

  late List<String> haptics;
  late _Deleter deleter;

  setUp(() {
    deleter = _Deleter();
    final before = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = before);
  });

  Photo photo(String task, String name, int ts) => Photo(
    taskId: task,
    taskName: name,
    dayKey: day,
    timestamp: ts,
    sessionSeconds: 60,
    photoUrl: 'https://x/$task-$ts.jpg',
    storagePath: '',
    cumulativeSeconds: ts,
  );

  /// Golf 1h and Piano 30m have photos, Chess 10m does not. Out of order on
  /// purpose: the row sorts them.
  final fourPhotos = [
    photo('tb', 'Piano', 4),
    photo('ta', 'Golf', 1),
    photo('ta', 'Golf', 3),
    photo('tb', 'Piano', 2),
  ];

  DayHistory history({
    int extraTasks = 0,
    DailyHabits? habits,
  }) {
    final times = [
      const TaskTime(name: 'Golf', seconds: 3600, taskId: 'ta'),
      const TaskTime(name: 'Piano', seconds: 1800, taskId: 'tb'),
      const TaskTime(name: 'Chess', seconds: 600, taskId: 'tc'),
      for (var i = 0; i < extraTasks; i++)
        TaskTime(name: 'Task $i', seconds: 60, taskId: 'x$i'),
    ];
    return DayHistory(
      dayKey: day,
      segments: [for (final t in times) t.seconds.toDouble()],
      taskIds: [for (final t in times) t.taskId],
      taskTimes: times,
      habits: habits,
    );
  }

  const twoHabits = DailyHabits(dayKey: day, ticks: [
    HabitTick(habitId: 'h1', name: 'Read', done: true),
    HabitTick(habitId: 'h2', name: 'Stretch', done: false),
  ]);

  Future<void> open(
    WidgetTester tester, {
    DayHistory? withHistory,
    List<Photo> photos = const [],
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: bottomInset * 3);
    addTearDown(tester.view.reset);
    haptics = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dayHistoryProvider.overrideWith((ref, key) => withHistory ?? history()),
          photosForDayProvider.overrideWith((ref, key) async => photos),
          photoDeleterProvider.overrideWithValue(deleter),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDayDetailSheet(context, day),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Rect sheet(WidgetTester tester) => tester.getRect(find.byType(BottomSheet));
  Finder date() => find.text('Thursday 1st October');
  Finder taskName(String name) => find.text(name);
  Color colourOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).style!.color!;
  GreyscaleTokens tokens(WidgetTester tester) => GreyscaleTokens.of(tester.element(date()));
  int? lit(WidgetTester tester) => tester
      .widget<SegmentedDial>(find.descendant(of: find.byKey(kDaySheetRingKey), matching: find.byType(SegmentedDial)))
      .selectedTaskIndex;
  ScrollPosition row(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byKey(kDaySheetPhotosKey), matching: find.byType(Scrollable)))
      .position;
  ScrollPosition body(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byKey(kDaySheetBodyKey), matching: find.byType(Scrollable)).first)
      .position;

  group('size', () {
    testWidgets('no drag handle; swipe down still dismisses', (tester) async {
      await open(tester);
      expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle, isNot(true));
      expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag, isTrue);
      await tester.fling(date(), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.byType(DayDetailSheet), findsNothing);
    });

    testWidgets('a day with no photos is short: it fits its content', (tester) async {
      await open(tester);
      final s = sheet(tester);
      expect(s.top, greaterThan(h * 0.25 + 100), reason: 'well under the ceiling');
      expect(s.bottom, h);
      expect(body(tester).maxScrollExtent, 0, reason: 'nothing to scroll');
      // Content, then 24 + the safe area.
      final last = tester.getRect(taskName('Chess'));
      expect(s.bottom - last.bottom, closeTo((30 - last.height) / 2 + 24 + bottomInset, 0.5));
    });

    testWidgets('a long day stops at today\'s ceiling, 211, and scrolls under a header that stays', (tester) async {
      await open(tester, withHistory: history(extraTasks: 30), photos: fourPhotos);
      expect(sheet(tester).top, closeTo(h * 0.25, 0.5));
      expect(sheet(tester).top, closeTo(211, 0.5));
      expect(body(tester).maxScrollExtent, greaterThan(0));
      final header = tester.getRect(date());
      await tester.drag(find.text('Chess'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(body(tester).pixels, greaterThan(0));
      expect(tester.getRect(date()), header, reason: 'the header is pinned');
      expect(find.byType(DayDetailSheet), findsOneWidget);
    });
  });

  group('header', () {
    testWidgets('date left on the gutter; 8 under it, time and habits in Metadata, supporting tone', (tester) async {
      await open(tester, withHistory: history(habits: twoHabits));
      final d = tester.getRect(date());
      expect(d.left, closeTo(24, 0.01));
      final summary = find.byKey(kDaySheetSummaryKey);
      expect(tester.widget<Text>(summary).data, '1h 40m logged · 1 of 2 habits');
      expect(tester.getRect(summary).top - d.bottom, closeTo(8, 0.01));
      final style = tester.widget<Text>(summary).style!;
      expect(style.fontSize, 12);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, tokens(tester).textSecondary);
      // The date keeps its string and its style.
      final dateStyle = tester.widget<Text>(date()).style!;
      expect(dateStyle.fontSize, 15);
      expect(dateStyle.fontWeight, FontWeight.w700);
    });

    testWidgets('no habits, no habits part', (tester) async {
      await open(tester);
      expect(tester.widget<Text>(find.byKey(kDaySheetSummaryKey)).data, '1h 40m logged');
    });

    testWidgets('the calendar\'s own ring at 44, on the right gutter, its top on the date\'s', (tester) async {
      await open(tester, photos: fourPhotos);
      final ring = find.byKey(kDaySheetRingKey);
      expect(tester.widget(ring), isA<CalendarDayRing>());
      final r = tester.getRect(ring);
      expect(r.size, const Size(44, 44));
      expect(r.right, closeTo(w - 24, 0.01));
      expect(r.top, closeTo(tester.getRect(date()).top, 0.01));
    });

    testWidgets('no photos: no slice lit', (tester) async {
      await open(tester);
      expect(lit(tester), isNull);
    });
  });

  group('photos', () {
    testWidgets('rounded exactly as the Profile milestones row is, the placeholder too', (tester) async {
      await open(tester, photos: fourPhotos);
      final ctx = tester.element(find.byKey(kDaySheetPhotosKey));
      final scale = figmaScale(ctx);
      final media = MediaQuery.of(ctx);
      // The milestones row's own tile, drawn in the same place, says what
      // its corners are.
      await tester.pumpWidget(
        MediaQuery(
          data: media,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Center(child: ProfileStripTile(child: SizedBox.expand())),
          ),
        ),
      );
      final strip = tester.widget<ClipRRect>(
        find.descendant(of: find.byType(ProfileStripTile), matching: find.byType(ClipRRect)),
      ).borderRadius;
      expect(strip, BorderRadius.circular(kProfileStripRadius * scale));

      await open(tester, photos: fourPhotos);
      for (var i = 0; i < 4; i++) {
        final clip = find.byKey(ValueKey('day-photo-$i'));
        expect(tester.widget<ClipRRect>(clip).borderRadius, strip);
        expect(tester.getSize(clip), const Size(200, 267));
        // The photo, and so its loading placeholder, is inside the clip.
        expect(find.descendant(of: clip, matching: find.byType(SondrPhoto)), findsOneWidget);
      }
    });

    testWidgets('200 × 267, 8 apart, the first on the gutter, chronological', (tester) async {
      await open(tester, photos: fourPhotos);
      final shots = find.descendant(of: find.byKey(kDaySheetPhotosKey), matching: find.byType(SondrPhoto));
      final first = tester.getRect(shots.at(0));
      final second = tester.getRect(shots.at(1));
      expect(first.size, const Size(200, 267));
      expect(first.left, closeTo(24, 0.01));
      expect(second.left - first.right, closeTo(8, 0.01));
      expect(first.top - tester.getRect(find.byKey(kDaySheetRingKey)).bottom, closeTo(24, 0.01));
      expect([for (var i = 0; i < 2; i++) tester.widget<SondrPhoto>(shots.at(i)).url],
          ['https://x/ta-1.jpg', 'https://x/tb-2.jpg']);
      // Free, like the Profile milestones row: no snapping.
      expect(row(tester).physics, isA<ClampingScrollPhysics>());
      expect(row(tester).maxScrollExtent, closeTo(24 + 4 * 200 + 3 * 8 + 24 - w, 0.01), reason: '24 trailing');
    });

    testWidgets('the current photo\'s task is lit, in the ring and the rows, and follows the scroll', (tester) async {
      await open(tester, photos: fourPhotos);
      final t = tokens(tester);
      expect(lit(tester), 0, reason: 'Golf, the first');
      expect(colourOf(tester, taskName('Golf')), t.textPrimary);
      expect(colourOf(tester, find.text('1h')), t.textSecondary);
      expect(colourOf(tester, taskName('Piano')), t.textTertiary);
      expect(colourOf(tester, find.text('30m')), t.textTertiary);
      expect(colourOf(tester, taskName('Chess')), t.textTertiary);

      // Nearest the gutter: 100 in is still the first; 110 is the second.
      row(tester).jumpTo(100);
      await tester.pump();
      expect(lit(tester), 0);
      row(tester).jumpTo(110);
      await tester.pump();
      expect(lit(tester), 1, reason: 'Piano');
      expect(colourOf(tester, taskName('Piano')), t.textPrimary);
      expect(colourOf(tester, taskName('Golf')), t.textTertiary);

      // A real drag does the same.
      await tester.drag(find.byKey(kDaySheetPhotosKey), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(row(tester).pixels, inInclusiveRange(1.5 * 208, 2.5 * 208));
      expect(lit(tester), 0, reason: 'the third photo is Golf');

      // At the end, the last photo — though the third is nearer the gutter.
      row(tester).jumpTo(row(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      expect((row(tester).maxScrollExtent / 208).round(), 2);
      expect(lit(tester), 1, reason: 'the last photo is Piano');
    });

    testWidgets('a long press: a light haptic, then the existing delete prompt and path', (tester) async {
      await open(tester, photos: fourPhotos);
      final shots = find.descendant(of: find.byKey(kDaySheetPhotosKey), matching: find.byType(SondrPhoto));
      await tester.longPress(shots.at(1));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(find.byType(BlurSheet), findsOneWidget);
      expect(find.text('Delete this photo?'), findsOneWidget);
      expect(find.text("It will be removed from Piano. This can't be undone."), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleter.deleted.single.timestamp, 2);
    });

    testWidgets('a tap opens nothing', (tester) async {
      await open(tester, photos: fourPhotos);
      final shots = find.descendant(of: find.byKey(kDaySheetPhotosKey), matching: find.byType(SondrPhoto));
      await tester.tap(shots.first);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewer), findsNothing);
      expect(find.byType(BlurSheet), findsNothing);
    });

    testWidgets('a day with no photos has no photo row, and the tasks start 24 under the header', (tester) async {
      await open(tester);
      expect(find.byKey(kDaySheetPhotosKey), findsNothing);
      // The header's bottom is the taller of its two sides: here the ring.
      final header = [
        tester.getRect(find.byKey(kDaySheetSummaryKey)).bottom,
        tester.getRect(find.byKey(kDaySheetRingKey)).bottom,
      ].reduce((a, b) => a > b ? a : b);
      final golf = tester.getRect(taskName('Golf'));
      expect(golf.top - (30 - golf.height) / 2 - header, closeTo(24, 0.5));
    });
  });

  group('tasks', () {
    testWidgets('30 tall, name left and time right in Supporting 13, tabular figures', (tester) async {
      await open(tester);
      final golf = tester.getRect(taskName('Golf'));
      final piano = tester.getRect(taskName('Piano'));
      expect(piano.top - golf.top, closeTo(30, 0.01));
      expect(golf.left, closeTo(24, 0.01));
      expect(tester.getRect(find.text('1h')).right, closeTo(w - 24, 0.01));
      final name = tester.widget<Text>(taskName('Golf')).style!;
      final time = tester.widget<Text>(find.text('1h')).style!;
      expect(name.fontSize, 13);
      expect(name.fontWeight, FontWeight.w400);
      expect(time.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('a row with a photo brings its first photo to the gutter, 300ms ease-out', (tester) async {
      await open(tester, photos: fourPhotos);
      await tester.tap(taskName('Piano'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(row(tester).pixels, inExclusiveRange(0, 208));
      expect(lit(tester), 1, reason: 'lit at once, not by the way through');
      await tester.pumpAndSettle();
      expect(row(tester).pixels, closeTo(208, 0.01));
      expect(lit(tester), 1);
      await tester.tap(taskName('Golf'));
      await tester.pumpAndSettle();
      expect(row(tester).pixels, 0);
      expect(lit(tester), 0);
    });

    testWidgets('a row without a photo is inert', (tester) async {
      await open(tester, photos: fourPhotos);
      row(tester).jumpTo(110);
      await tester.pump();
      await tester.tap(taskName('Chess'));
      await tester.pumpAndSettle();
      expect(row(tester).pixels, 110);
      expect(lit(tester), 1);
    });

    testWidgets('no photos: every name primary, every time secondary, nothing tappable', (tester) async {
      await open(tester);
      final t = tokens(tester);
      for (final (name, time) in [('Golf', '1h'), ('Piano', '30m'), ('Chess', '10m')]) {
        expect(colourOf(tester, taskName(name)), t.textPrimary, reason: name);
        expect(colourOf(tester, find.text(time)), t.textSecondary, reason: time);
        final tap = tester.widget<GestureDetector>(
          find.ancestor(of: taskName(name), matching: find.byType(GestureDetector)).first,
        );
        expect(tap.onTap, isNull, reason: name);
      }
    });
  });

  group('habits', () {
    testWidgets('10, a hairline on the gutters, 10, then one 30 row each: the name alone, white if done, grey if not', (tester) async {
      await open(tester, withHistory: history(habits: twoHabits));
      final t = tokens(tester);
      final rule = find.byWidgetPredicate((w) => w is ColoredBox && w.color == kHairline);
      expect(rule, findsOneWidget);
      final r = tester.getRect(rule);
      expect(r.height, 1);
      expect(r.left, closeTo(24, 0.01));
      expect(r.right, closeTo(w - 24, 0.01));
      final chess = tester.getRect(taskName('Chess'));
      expect(r.top - (chess.bottom + (30 - chess.height) / 2), closeTo(10, 0.5));
      final read = tester.getRect(find.text('Read'));
      expect(read.top - (30 - read.height) / 2 - r.bottom, closeTo(10, 0.5));
      expect(tester.getRect(find.text('Stretch')).top - read.top, closeTo(30, 0.01));
      expect(find.text('Done'), findsNothing);
      expect(find.text('Not done'), findsNothing);
      expect(colourOf(tester, find.text('Read')), t.textPrimary);
      expect(colourOf(tester, find.text('Stretch')), t.textTertiary);
      // Nothing on the right of a habit row.
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Read'), matching: find.byType(Row)).first,
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(find.text('Read')).left, closeTo(24, 0.01));
    });

    testWidgets('a day without habits has no hairline and no habit rows', (tester) async {
      await open(tester);
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == kHairline), findsNothing);
      expect(find.text('Done'), findsNothing);
      expect(find.text('Not done'), findsNothing);
    });
  });

  group('the ring\'s dot', () {
    testWidgets('no white dot for more than one photo, in the sheet or the calendar', (tester) async {
      await open(tester, photos: fourPhotos);
      final ring = find.byKey(kDaySheetRingKey);
      expect(
        find.descendant(of: ring, matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        )),
        findsNothing,
      );
      expect(find.descendant(of: ring, matching: find.byType(Positioned)), findsNothing);
    });
  });

  group('what went', () {
    testWidgets('no big dial, no "Captured", no "Time per task", no "Habits ·" heading', (tester) async {
      await open(tester, withHistory: history(habits: twoHabits), photos: fourPhotos);
      expect(find.byWidgetPredicate((w) => w is SegmentedDial && w.size > 44), findsNothing);
      expect(find.text('Captured'), findsNothing);
      expect(find.text('Time per task'), findsNothing);
      expect(find.textContaining('Habits ·'), findsNothing);
      expect(find.text('logged'), findsNothing, reason: 'the ring\'s old label');
    });
  });

  for (final ts in [0.824, 1.0, 1.235]) {
    testWidgets('at textScaler $ts: nothing overflows, the header stays, the ring stays 44', (tester) async {
      await open(tester, withHistory: history(extraTasks: 30, habits: twoHabits), photos: fourPhotos, textScale: ts);
      expect(tester.takeException(), isNull);
      expect(sheet(tester).top, closeTo(211, 0.5));
      expect(tester.getRect(find.byKey(kDaySheetRingKey)).size, const Size(44, 44));
      final header = tester.getRect(date());
      await tester.drag(find.text('Chess'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(date()), header);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Deleter implements PhotoDeleter {
  final List<Photo> deleted = [];

  @override
  Future<int?> milestoneHoursOf(Photo photo) async => null;

  @override
  Future<void> removeFromCollages(Photo photo) async {}

  @override
  Future<void> deletePhoto(Photo photo) async => deleted.add(photo);
}
