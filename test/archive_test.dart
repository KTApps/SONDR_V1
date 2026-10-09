import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/milestones_screen.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

/// Archiving is a statement about what you are working on NOW. The whole point
/// of these tests is the line it must not cross: the choosing surfaces lose the
/// task, every record of its hours keeps it.
void main() {
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
      expect(find.text('Add Task'), findsOneWidget);
      expect(archiveToggle(), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('the Archive toggle is styled exactly like Add Task', (
      tester,
    ) async {
      // Equal standing: same size, same weight, same tone. Hierarchy between
      // them comes from position alone.
      await openMenu(tester);
      final add = tester.widget<Text>(find.text('Add Task')).style!;
      final archive = tester.widget<Text>(archiveToggle()).style!;
      expect(archive.fontSize, add.fontSize);
      expect(archive.fontWeight, add.fontWeight);
      expect(archive.color, add.color);
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
      expect(find.text('Add Task'), findsNothing);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Golf'), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Golf'), findsOneWidget);
      expect(find.text('Add Task'), findsOneWidget);
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
      expect(find.text('Add Task'), findsNothing);
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
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: TaskDropdown())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final c = containerOf(tester);
      c.read(timerControllerProvider.notifier).start();
      // Paused still counts as active, and cancels the ticker so the test
      // leaves no pending timer behind.
      c.read(timerControllerProvider.notifier).pause();
      await tester.pumpAndSettle();
      expect(c.read(timerControllerProvider).isActive, isTrue);

      await tapSelector(tester);
      expect(find.text('Add Task'), findsNothing);
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
