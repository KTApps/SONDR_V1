import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';
import 'package:sondr/shared/sondr_field.dart';

/// Naming a task happens in the list, not in a dialog over it.
///
/// "Add Task" used to pop the sheet and open a prompt, so you lost sight of
/// the tasks you already had at the moment you were deciding what to call the
/// next one. The draft is a pill in the same list, in the same place the task
/// will be.
void main() {
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
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TaskDropdown)));

  Finder draftField() => find.byType(SondrField);

  testWidgets('"Add Task" opens a draft pill, focused, with the sheet still '
      'open', (tester) async {
    await openMenu(tester);
    expect(draftField(), findsNothing);
    final before = containerOf(tester).read(tasksProvider).value!.length;

    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();

    // The field is there and has the keyboard.
    expect(draftField(), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    // The sheet stayed open — the existing tasks are still on screen.
    expect(find.text('Add Task'), findsOneWidget);
    // And nothing has been created yet.
    expect(containerOf(tester).read(tasksProvider).value!.length, before);

    // The draft looks like the task it is about to become: the pill's own
    // 12, bold, and centred.
    final field = tester.widget<SondrField>(draftField());
    expect(field.fontSize, 12);
    expect(field.filled, isFalse);
    expect(field.centered, isTrue);
    expect(field.autofocus, isTrue);
    expect(field.textInputAction, TextInputAction.done);
  });

  testWidgets('Return with a name creates it, selects it, and closes', (
    tester,
  ) async {
    await openMenu(tester);
    final before = containerOf(tester).read(tasksProvider).value!.length;

    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Pottery');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final container = containerOf(tester);
    final tasks = container.read(tasksProvider).value!;
    expect(tasks.length, before + 1);
    final created = tasks.firstWhere((t) => t.name == 'Pottery');
    // Selected, and starting from nothing.
    expect(container.read(selectedTaskIdProvider), created.id);
    expect(created.totalSeconds, 0);
    expect(created.milestoneProgress, 0);
    // The sheet closed.
    expect(find.text('Add Task'), findsNothing);
  });

  testWidgets('Return with nothing typed creates nothing and keeps the sheet', (
    tester,
  ) async {
    await openMenu(tester);
    final before = containerOf(tester).read(tasksProvider).value!.length;

    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(tasksProvider).value!.length, before);
    // The draft is gone, the sheet is not.
    expect(draftField(), findsNothing);
    expect(find.text('Add Task'), findsOneWidget);
  });

  testWidgets('whitespace alone is nothing typed', (tester) async {
    await openMenu(tester);
    final before = containerOf(tester).read(tasksProvider).value!.length;

    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(tasksProvider).value!.length, before);
    expect(find.text('Add Task'), findsOneWidget);
  });

  testWidgets('tapping "Add Task" twice gives ONE draft, and does not wipe '
      'what you have typed', (tester) async {
    await openMenu(tester);
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Half typed');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();

    expect(draftField(), findsOneWidget);
    // The second tap is a no-op, not a reset: re-opening would clear the
    // controller and throw away a name halfway through being typed.
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Half typed',
    );
  });

  testWidgets('the draft sits ABOVE the tasks already there', (tester) async {
    await openMenu(tester);
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();

    // Nothing in the list starts higher up than the draft.
    final draftTop = tester.getTopLeft(draftField()).dy;
    for (final pill in tester.widgetList<Text>(find.byType(Text))) {
      final label = pill.data;
      if (label == null || label == 'Add Task' || label == 'Archive') continue;
      final finder = find.text(label);
      if (finder.evaluate().length != 1) continue;
      expect(
        tester.getTopLeft(finder).dy,
        greaterThanOrEqualTo(draftTop - 0.01),
        reason: '"$label" sits above the draft',
      );
    }
  });

  test('the controller refuses a nameless task', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(tasksProvider.notifier).addTask('   '),
      throwsArgumentError,
    );
  });
}
