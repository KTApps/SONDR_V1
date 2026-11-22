import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/firestore_tasks_repository.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

/// Renaming a task: a word in the active tray, the pill becoming the draft's
/// field with the name in it, and Return saving only a real change. The
/// task's private photos take the new name; posts and notices keep theirs.
void main() {
  group('the controller', () {
    Future<(ProviderContainer, Task)> seeded() async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final tasks = await c.read(tasksProvider.future);
      return (c, tasks.firstWhere((t) => t.name == 'Golf'));
    }

    test('a new name is saved, and nothing else about the task moves', () async {
      final (c, golf) = await seeded();
      expect(await c.read(tasksProvider.notifier).renameTask(golf.id, '  Putting  '), isTrue);
      final after = c.read(tasksProvider).value!.firstWhere((t) => t.id == golf.id);
      expect(after.name, 'Putting');
      expect(after.secondsByDay, golf.secondsByDay);
      expect(after.archived, golf.archived);
      expect(c.read(activeTasksProvider).map((t) => t.name), contains('Putting'));
    });

    test('empty or unchanged is a cancel', () async {
      final (c, golf) = await seeded();
      final notifier = c.read(tasksProvider.notifier);
      expect(await notifier.renameTask(golf.id, ''), isFalse);
      expect(await notifier.renameTask(golf.id, '   '), isFalse);
      expect(await notifier.renameTask(golf.id, 'Golf'), isFalse);
      expect(await notifier.renameTask(golf.id, ' Golf '), isFalse);
      expect(await notifier.renameTask('nope', 'Anything'), isFalse);
      expect(c.read(tasksProvider).value!.firstWhere((t) => t.id == golf.id).name, 'Golf');
    });

    test('the selected task follows the rename', () async {
      final (c, golf) = await seeded();
      c.read(selectedTaskIdProvider.notifier).select(golf.id);
      await c.read(tasksProvider.notifier).renameTask(golf.id, 'Putting');
      expect(c.read(selectedTaskProvider)!.name, 'Putting');
    });
  });

  group('the photos', () {
    late FakeFirebaseFirestore db;
    late FirestoreTasksRepository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestoreTasksRepository(db: db, uid: 'me');
      await db.doc('users/me/tasks/golf').set({'name': 'Golf', 'createdAt': 1});
    });

    Future<void> photo(String id, String taskId, String name, {String uid = 'me'}) =>
        db.doc('users/$uid/photos/$id').set({'taskId': taskId, 'taskName': name, 'timestamp': 1});

    Future<String?> nameOf(String id, {String uid = 'me'}) async =>
        (await db.doc('users/$uid/photos/$id').get()).data()?['taskName'] as String?;

    test('the task doc and every one of its photos take the new name', () async {
      for (var i = 0; i < 7; i++) {
        await photo('g$i', 'golf', 'Golf');
      }
      await photo('other', 'piano', 'Piano');
      await photo('theirs', 'golf', 'Golf', uid: 'them');

      // A small batch limit, so the batches are really split.
      await repo.rename('golf', 'Putting', batchLimit: 3);

      expect((await db.doc('users/me/tasks/golf').get()).data()!['name'], 'Putting');
      for (var i = 0; i < 7; i++) {
        expect(await nameOf('g$i'), 'Putting');
      }
      expect(await nameOf('other'), 'Piano', reason: 'another task');
      expect(await nameOf('theirs', uid: 'them'), 'Golf', reason: 'someone else');
    });

    test('running it again is safe, and finishes one cut off partway', () async {
      await photo('a', 'golf', 'Putting'); // already renamed
      await photo('b', 'golf', 'Golf'); // the one a cut-off run missed
      await repo.rename('golf', 'Putting');
      await repo.rename('golf', 'Putting');
      expect(await nameOf('a'), 'Putting');
      expect(await nameOf('b'), 'Putting');
    });

    test('the createdAt ordering key survives', () async {
      await repo.rename('golf', 'Putting');
      expect((await db.doc('users/me/tasks/golf').get()).data()!['createdAt'], 1);
    });
  });

  group('the tray', () {
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
      await tester.tap(find.byType(TaskDropdown));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(TaskDropdown)));

    Finder row(String name) =>
        find.descendant(of: find.byType(SondrSwipeRow), matching: find.text(name));

    Finder tray(String label) => find
        .descendant(of: find.byType(SondrSwipeRow), matching: find.text(label).hitTestable())
        .hitTestable();

    Future<void> swipe(WidgetTester tester, String name) async {
      await tester.drag(row(name), const Offset(-200, 0));
      await tester.pumpAndSettle();
    }

    TextField field(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

    testWidgets('the active tray offers Rename first, then Archive, in one style', (tester) async {
      await openMenu(tester);
      await swipe(tester, 'Golf');
      expect(tray('Rename'), findsOneWidget);
      expect(tray('Archive'), findsOneWidget);
      final rename = tester.getRect(tray('Rename'));
      final archive = tester.getRect(tray('Archive'));
      expect(rename.left, lessThan(archive.left), reason: 'Rename first');
      expect(rename.center.dy, closeTo(archive.center.dy, 0.5));
      final a = tester.widget<Text>(tray('Rename')).style!;
      final b = tester.widget<Text>(tray('Archive')).style!;
      expect(a.fontSize, b.fontSize);
      expect(a.fontWeight, b.fontWeight);
      expect(a.color, b.color);
    });

    testWidgets('the archived tray is unchanged: no Rename', (tester) async {
      await openMenu(tester);
      await swipe(tester, 'Golf');
      await tester.tap(tray('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      await swipe(tester, 'Golf');
      expect(tray('Unarchive'), findsOneWidget);
      expect(tray('Delete'), findsOneWidget);
      expect(find.text('Rename'), findsNothing);
    });

    testWidgets('Rename turns the pill into the field, full, cursor at the end, keyboard up', (tester) async {
      await openMenu(tester);
      await swipe(tester, 'Golf');
      await tester.tap(tray('Rename'));
      await tester.pumpAndSettle();
      final f = field(tester);
      expect(f.controller!.text, 'Golf');
      expect(f.controller!.selection, const TextSelection.collapsed(offset: 4));
      expect(f.autofocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(f.textInputAction, TextInputAction.done);
    });

    testWidgets('Return with a new name saves it, and the tray stays open', (tester) async {
      await openMenu(tester);
      await swipe(tester, 'Golf');
      await tester.tap(tray('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Putting');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(row('Putting'), findsOneWidget, reason: 'the pill, renamed, in the open tray');
      expect(row('Golf'), findsNothing);
      expect(find.text('Add task'), findsOneWidget, reason: 'still open');
      expect(containerOf(tester).read(activeTasksProvider).map((t) => t.name), contains('Putting'));
    });

    testWidgets('the selector shows the new name of the selected task', (tester) async {
      await openMenu(tester);
      await tester.tap(row('Golf'));
      await tester.pumpAndSettle();
      expect(find.text('Golf'), findsOneWidget, reason: 'the selector');
      await tester.tap(find.byType(TaskDropdown));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await swipe(tester, 'Golf');
      await tester.tap(tray('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Putting');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // The pill and the selector behind the sheet.
      expect(find.text('Putting'), findsNWidgets(2));
      expect(find.text('Golf'), findsNothing);
    });

    for (final typed in ['', '   ', 'Golf']) {
      testWidgets('Return on "$typed" is a cancel', (tester) async {
        await openMenu(tester);
        await swipe(tester, 'Golf');
        await tester.tap(tray('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), typed);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(row('Golf'), findsOneWidget);
        expect(find.text('Add task'), findsOneWidget);
        expect(containerOf(tester).read(activeTasksProvider).map((t) => t.name), contains('Golf'));
      });
    }

    testWidgets('Add task closes a rename, and only one field is ever open', (tester) async {
      await openMenu(tester);
      await swipe(tester, 'Golf');
      await tester.tap(tray('Rename'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(field(tester).controller!.text, '');
      expect(row('Golf'), findsOneWidget);
    });
  });
}
