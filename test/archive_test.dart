import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/milestones_screen.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/tasks/delete_task.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

/// Archiving is a statement about what you are working on NOW. The whole point
/// of these tests is the line it must not cross: the choosing surfaces lose the
/// task, every record of its hours keeps it.
void main() async {
  group('the model', () {
    test('a task is active by default', () {
      expect(const Task(id: 't', name: 'Golf').archived, isFalse);
    });

    test('archived round-trips through the map', () {
      final t = const Task(id: 't', name: 'Golf').archivedAs(true);
      expect(Task.fromMap('t', t.toMap()).archived, isTrue);
      expect(Task.fromMap('t', t.archivedAs(false).toMap()).archived, isFalse);
    });

    test('a document written before the field existed reads as active', () {
      final legacy = const Task(id: 't', name: 'Golf').toMap()
        ..remove('archived');
      expect(legacy.containsKey('archived'), isFalse);
      expect(Task.fromMap('t', legacy).archived, isFalse);
    });

    test('a non-bool value is not mistaken for archived', () {
      final odd = const Task(id: 't', name: 'Golf').toMap()
        ..['archived'] = 'yes';
      expect(Task.fromMap('t', odd).archived, isFalse);
    });

    test('archiving carries the history across, untouched', () {
      final worked = const Task(
        id: 't',
        name: 'Golf',
        secondsByDay: {'2026-10-01': 7200},
      );
      final away = worked.archivedAs(true);
      expect(away.secondsByDay, worked.secondsByDay);
      expect(away.totalSeconds, 7200);
    });

    test('logging time onto an archived task leaves it archived', () {
      // save() merges toMap(), so a lost flag here would quietly un-archive a
      // task the moment anything wrote to it.
      final away = const Task(id: 't', name: 'Golf').archivedAs(true);
      final later = away.addingSeconds(600, DateTime(2026, 10, 8));
      expect(later.archived, isTrue);
      expect(later.totalSeconds, 600);
    });
  });

  group('the lists', () {
    Future<(ProviderContainer, Task)> seeded() async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final tasks = await c.read(tasksProvider.future);
      return (c, tasks.firstWhere((t) => t.name == 'Golf'));
    }

    test('active and archived partition the task list', () async {
      final (c, golf) = await seeded();
      final total = c.read(tasksProvider).value!.length;

      expect(c.read(activeTasksProvider).length, total);
      expect(c.read(archivedTasksProvider), isEmpty);

      await c.read(tasksProvider.notifier).setArchived(golf.id, true);

      expect(c.read(activeTasksProvider).length, total - 1);
      expect(c.read(activeTasksProvider).any((t) => t.id == golf.id), isFalse);
      expect(c.read(archivedTasksProvider).map((t) => t.id), [golf.id]);
      // The task itself is still there — archiving is not deleting.
      expect(c.read(tasksProvider).value!.length, total);
    });

    test('unarchiving puts it back', () async {
      final (c, golf) = await seeded();
      await c.read(tasksProvider.notifier).setArchived(golf.id, true);
      await c.read(tasksProvider.notifier).setArchived(golf.id, false);
      expect(c.read(archivedTasksProvider), isEmpty);
      expect(c.read(activeTasksProvider).any((t) => t.id == golf.id), isTrue);
    });

    test('archiving an already-archived task changes nothing', () async {
      final (c, golf) = await seeded();
      await c.read(tasksProvider.notifier).setArchived(golf.id, true);
      final before = c.read(archivedTasksProvider);
      await c.read(tasksProvider.notifier).setArchived(golf.id, true);
      expect(c.read(archivedTasksProvider).length, before.length);
    });

    test('an unknown id is ignored', () async {
      final (c, _) = await seeded();
      await c.read(tasksProvider.notifier).setArchived('nope', true);
      expect(c.read(archivedTasksProvider), isEmpty);
    });

    test('the lifetime figures still count an archived task', () async {
      // The hero's hours and milestones are a RECORD. Putting a task away must
      // not quietly subtract the hours it earned.
      final (c, golf) = await seeded();
      final hours = c.read(lifetimeDurationProvider);
      final milestones = c.read(milestonesReachedProvider);
      expect(milestones, greaterThan(0)); // Golf is just past 20h

      await c.read(tasksProvider.notifier).setArchived(golf.id, true);

      expect(c.read(lifetimeDurationProvider), hours);
      expect(c.read(milestonesReachedProvider), milestones);
    });
  });

  group('the dropdown', () {
    /// Tap the selector and wait out the double-tap window.
    ///
    /// Once a task is picked the selector also carries an onDoubleTap (the
    /// snap-back-to-overview shortcut), so its single tap is held for ~300ms
    /// to see whether a second one follows. pumpAndSettle schedules no frames
    /// in that window, so the tap would otherwise never land.
    Future<void> tapSelector(WidgetTester tester) async {
      await tester.tap(find.byType(TaskDropdown));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: TaskDropdown())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapSelector(tester);
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(TaskDropdown)));

    /// The PILL named [name], not the selector above it — once a task is
    /// picked, the selector shows the same word.
    Finder row(String name) => find.descendant(
      of: find.byType(SondrSwipeRow),
      matching: find.text(name),
    );

    /// The OPEN swipe tray's action. Every row builds its tray, so the word is
    /// in the tree once per row; only the uncovered one can be hit.
    Finder tray(String label) => find
        .descendant(of: find.byType(SondrSwipeRow), matching: find.text(label))
        .hitTestable();

    /// The footer's "Archive" toggle — which now shares its word with the
    /// trays above it. The footer sits after the pill list in the panel's
    /// Stack, so it is the last match.
    Finder archiveToggle() => find.text('Archive').last;

    testWidgets('lists the active tasks, with both footer actions', (
      tester,
    ) async {
      await openMenu(tester);
      expect(find.text('Golf'), findsOneWidget);
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('Add task'), findsOneWidget);
      expect(archiveToggle(), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('the Archive toggle is the same SIZE as Add task, and a '
        'quieter tone', (tester) async {
      // They used to match outright, told apart by position alone. The sheet
      // is for choosing and adding; putting a task away is the side door, so
      // it steps back to the tone "Back" wears in the view it opens. The SIZE
      // still matches, because the footer's height is a measured constant the
      // panel's geometry depends on.
      await openMenu(tester);
      final add = tester.widget<Text>(find.text('Add task')).style!;
      final archive = tester.widget<Text>(archiveToggle()).style!;
      expect(archive.fontSize, add.fontSize);
      expect(add.fontWeight, FontWeight.w700);
      expect(archive.fontWeight, FontWeight.w400);
      expect(archive.color, isNot(add.color));
    });

    testWidgets('"Archive" swaps the sheet, "Back" swaps it straight back', (
      tester,
    ) async {
      await openMenu(tester);

      await tester.tap(archiveToggle());
      await tester.pumpAndSettle();
      expect(find.text('No archived tasks.'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      // The archived view carries neither the add nor a second toggle, and
      // with no rows there is no tray to borrow the word either.
      expect(find.text('Add task'), findsNothing);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Golf'), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Golf'), findsOneWidget);
      expect(find.text('Add task'), findsOneWidget);
      expect(find.text('No archived tasks.'), findsNothing);
    });

    testWidgets('swiping a row LEFT reveals Archive, and it archives', (
      tester,
    ) async {
      await openMenu(tester);
      // The tray is always BUILT (clipped to nothing until opened), so the
      // question is whether it can be reached, not whether it exists.
      expect(tray('Archive'), findsNothing);

      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tray('Archive'), findsOneWidget);

      await tester.tap(tray('Archive'));
      await tester.pumpAndSettle();

      // Gone from the active list, and on the archived one with the reverse.
      expect(find.text('Golf'), findsNothing);
      expect(containerOf(tester).read(archivedTasksProvider).length, 1);

      await tester.tap(archiveToggle());
      await tester.pumpAndSettle();
      expect(find.text('Golf'), findsOneWidget);
      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tray('Unarchive'), findsOneWidget);
    });

    Future<void> openMenuWith(
      WidgetTester tester, {
      required TaskPurge purge,
      required SessionStore store,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskPurgeProvider.overrideWithValue(purge),
            sessionStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: TaskDropdown())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapSelector(tester);
    }

    testWidgets('archiving a row leaves the row that moves up CLOSED', (
      tester,
    ) async {
      // The seed lists Spanish, Piano, Golf. Archive the first: Piano moves
      // up into its slot. Keyed by slot it arrived already swiped open and
      // looked untouched; keyed by task it arrives shut.
      await openMenu(tester);
      await tester.drag(row('Spanish'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tray('Archive'), findsOneWidget);

      await tester.tap(tray('Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Spanish'), findsNothing);
      expect(row('Piano'), findsOneWidget);
      expect(row('Golf'), findsOneWidget);
      expect(tray('Archive'), findsNothing, reason: 'no row is left open');
      expect(containerOf(tester).read(activeTasksProvider).map((t) => t.name),
          unorderedEquals(['Piano', 'Golf']));
    });

    testWidgets('Delete is not offered in the active list\'s tray', (
      tester,
    ) async {
      await openMenu(tester);
      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tray('Archive'), findsOneWidget);
      expect(tray('Delete'), findsNothing);
    });

    testWidgets('the archived tray offers Delete; Cancel changes nothing', (
      tester,
    ) async {
      final purge = _FakePurge(photos: 2);
      await openMenuWith(tester, purge: purge, store: _NoStore());
      final c = containerOf(tester);
      final golf = c.read(tasksProvider).value!.firstWhere((t) => t.name == 'Golf');

      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(tray('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(archiveToggle());
      await tester.pumpAndSettle();

      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tray('Unarchive'), findsOneWidget);
      expect(tray('Delete'), findsOneWidget);

      await tester.tap(tray('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Golf?'), findsOneWidget);
      expect(
        find.text(deleteTaskBody(
          hours: golf.wholeHours,
          milestones: golf.milestonesReached,
          photos: 2,
        )),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Golf?'), findsNothing);
      expect(c.read(tasksProvider).value!.length, 3);
      expect(c.read(archivedTasksProvider).map((t) => t.name), ['Golf']);
      expect(purge.deletedPhotos, isEmpty);
      expect(purge.deletedCollages, isEmpty);
    });

    testWidgets('Delete removes the task, its photos and collages, and clears the selection', (
      tester,
    ) async {
      final purge = _FakePurge(photos: 2);
      final store = _NoStore();
      await openMenuWith(tester, purge: purge, store: store);
      final c = containerOf(tester);
      final golf = c.read(tasksProvider).value!.firstWhere((t) => t.name == 'Golf');

      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(tray('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(archiveToggle());
      await tester.pumpAndSettle();
      // Selected and named by the stored session — both must be let go of.
      c.read(selectedTaskIdProvider.notifier).select(golf.id);
      store.saved = SessionClock(startedAt: DateTime(2026), taskId: golf.id);

      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(tray('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last); // the prompt's, above the tray's
      await tester.pumpAndSettle();

      expect(c.read(tasksProvider).value!.map((t) => t.name), ['Spanish', 'Piano']);
      expect(c.read(archivedTasksProvider), isEmpty);
      expect(purge.deletedPhotos, [golf.id]);
      expect(purge.deletedCollages, [golf.id]);
      expect(c.read(selectedTaskIdProvider), isNull);
      expect(store.saved, isNull);
      expect(find.text('Golf'), findsNothing);
    });

    testWidgets('swiping the other way leaves the tray shut', (tester) async {
      await openMenu(tester);
      await tester.drag(row('Golf'), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(tray('Archive'), findsNothing);
    });

    testWidgets('tapping a row still picks that task', (tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Spanish'));
      await tester.pumpAndSettle();
      // The sheet closed and the selector now names it.
      expect(find.text('Add task'), findsNothing);
      final c = containerOf(tester);
      expect(c.read(selectedTaskProvider)?.name, 'Spanish');
    });

    testWidgets('archiving the selected task drops the dial to the overview', (
      tester,
    ) async {
      await openMenu(tester);
      await tester.tap(find.text('Golf'));
      await tester.pumpAndSettle();
      final c = containerOf(tester);
      expect(c.read(selectedTaskProvider)?.name, 'Golf');

      await tapSelector(tester);
      await tester.drag(row('Golf'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(tray('Archive'));
      await tester.pumpAndSettle();

      // No ghost: nothing is selected, so Home is back on the collective
      // overview with no timer controls pointing at a put-away task.
      expect(c.read(selectedTaskIdProvider), isNull);
      expect(c.read(selectedTaskProvider), isNull);
    });

    testWidgets('the sheet cannot be opened while a session is active', (
      tester,
    ) async {
      // This is what makes a running timer unorphanable: the one way to
      // archive is through a sheet that a live session locks shut.
      await tester.pumpWidget(
        ProviderScope(
          // The controller reads the stored session before it starts one,
          // and the real store is a platform channel that never answers in
          // a widget test.
          overrides: [sessionStoreProvider.overrideWithValue(_NoStore())],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: TaskDropdown())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final c = containerOf(tester);
      await c.read(timerControllerProvider.notifier).start();
      // Paused still counts as active, and cancels the ticker so the test
      // leaves no pending timer behind.
      await c.read(timerControllerProvider.notifier).pause();
      await tester.pumpAndSettle();
      expect(c.read(timerControllerProvider).isActive, isTrue);

      await tapSelector(tester);
      expect(find.text('Add task'), findsNothing);
      expect(find.text('Archive'), findsNothing);
    });
  });

  testWidgets('the Milestones page still shows an archived task', (
    tester,
  ) async {
    // The one hard guarantee: archiving touches what you choose from, never
    // the history. Golf is just past 20h, so it has a milestone row.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final tasks = await c.read(tasksProvider.future);
    final golf = tasks.firstWhere((t) => t.name == 'Golf');
    await c.read(tasksProvider.notifier).setArchived(golf.id, true);
    expect(c.read(activeTasksProvider).any((t) => t.id == golf.id), isFalse);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MilestonesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Golf'), findsOneWidget);
  });
}

/// Keeps a session in memory. The real store is a platform channel, and a
/// widget test has nothing on the other end of it.
class _NoStore implements SessionStore {
  SessionClock? saved;

  @override
  Future<SessionClock?> read() async => saved;

  @override
  Future<void> write(SessionClock clock) async => saved = clock;

  @override
  Future<void> clear() async => saved = null;
}

class _FakePurge implements TaskPurge {
  _FakePurge({required this.photos});
  final int photos;
  final List<String> deletedPhotos = [];
  final List<String> deletedCollages = [];

  @override
  Future<int> photoCount(String taskId) async => photos;
  @override
  Future<void> deletePhotos(String taskId) async => deletedPhotos.add(taskId);
  @override
  Future<void> deleteCollages(String taskId) async => deletedCollages.add(taskId);
}
