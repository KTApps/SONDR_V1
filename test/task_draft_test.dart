import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

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

  /// Re-open the sheet after a task has been chosen.
  ///
  /// Once something is selected the selector also listens for a DOUBLE tap,
  /// so the single tap is held in the arena until that window closes —
  /// and pumpAndSettle returns before it, because a pending gesture timer
  /// schedules no frames. Without the wait the sheet never opens and every
  /// assertion after it is made against an empty screen.
  Future<void> reopenMenu(WidgetTester tester) async {
    await tester.tap(find.byType(TaskDropdown));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TaskDropdown)));

  Finder draftField() => find.byType(TextField);

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
    // 12 bold, centred both ways, on the label's own line box.
    final scale = figmaScale(tester.element(find.byType(TaskDropdown)));
    final field = tester.widget<TextField>(draftField());
    expect(field.style!.fontSize, closeTo(12 * scale, 0.01));
    expect(field.style!.fontWeight, FontWeight.w700);
    expect(field.style!.color, const Color(0xFFFAFAFA));
    expect(field.textAlign, TextAlign.center);
    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(field.autofocus, isTrue);
    expect(field.textInputAction, TextInputAction.done);
    // The caret is the label's line, not the field's default idea of one.
    expect(field.strutStyle!.forceStrutHeight, isTrue);
    expect(
      field.cursorHeight,
      closeTo(12 * scale * 1.4, 0.01),
      reason: 'the caret is not the height of the label it is typing',
    );
    expect(field.cursorWidth, closeTo(1.5 * scale, 0.01));
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

  testWidgets('the selected task is not outlined in the list', (tester) async {
    await openMenu(tester);
    final container = containerOf(tester);
    final tasks = container.read(tasksProvider).value!;
    // Make sure there IS something to outline: the first version of this
    // test reopened the sheet, found no pills at all, and passed on an empty
    // list — it went on passing with the border put back.
    expect(tasks, isNotEmpty, reason: 'nothing in the list to check');
    container.read(selectedTaskIdProvider.notifier).select(tasks.first.id);
    await tester.pumpAndSettle();

    final pills = find.byType(SondrSwipeRow);
    expect(pills, findsAtLeastNWidgets(1));
    final bordered = find
        .descendant(
          of: pills,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration?)?.border != null,
          ),
        )
        .evaluate();
    expect(bordered, isEmpty, reason: 'a pill is still outlined');
  });

  testWidgets('"Archive" is supporting, "Add Task" is not', (tester) async {
    await openMenu(tester);
    // Every pill builds a swipe tray, and the tray's word is "Archive" too —
    // so the footer's one is the copy that is NOT inside a row.
    TextStyle styleOf(String label) {
      final inRows = find
          .descendant(
            of: find.byType(SondrSwipeRow),
            matching: find.text(label),
          )
          .evaluate()
          .toSet();
      final footer = find
          .text(label)
          .evaluate()
          .where((e) => !inRows.contains(e))
          .toList();
      expect(footer, hasLength(1), reason: 'one footer "$label" expected');
      return (footer.single.widget as Text).style!;
    }

    // The same size, so the row's measured height is unchanged.
    expect(styleOf('Archive').fontSize, styleOf('Add Task').fontSize);
    // Told apart by weight and tone, the way "Back" is in the view it opens.
    expect(styleOf('Add Task').fontWeight, FontWeight.w700);
    expect(styleOf('Archive').fontWeight, FontWeight.w400);
    expect(styleOf('Add Task').color, const Color(0xFFFAFAFA));
    expect(styleOf('Archive').color, const Color(0xFFB0B0B0));

    // And it still opens the archived view. The trays sit behind their
    // pills, so the footer's copy is the only one a finger can reach.
    await tester.tap(find.text('Archive').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Back'), findsOneWidget);
    expect(styleOf('Back').color, const Color(0xFFB0B0B0));
  });

  /// The capsule a given field or label sits on.
  Rect pillOf(WidgetTester tester, Finder inner) => tester.getRect(
    find.ancestor(of: inner, matching: find.byType(ClipRRect)).first,
  );

  testWidgets('the caret sits on the line the name will, not at the pill top', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();

    final pill = pillOf(tester, draftField());
    final caret = tester.getRect(find.byType(EditableText));

    // It used to start at the pill's very top edge, 6.5 above centre.
    expect(
      caret.center.dy,
      closeTo(pill.center.dy, 0.5),
      reason: 'the caret is off centre in the pill',
    );
    // Inside, with the same air above and below.
    expect(caret.top, greaterThan(pill.top));
    expect(caret.bottom, lessThan(pill.bottom));
    expect(
      caret.top - pill.top,
      closeTo(pill.bottom - caret.bottom, 0.5),
      reason: 'the margins above and below the caret differ',
    );
  });

  testWidgets('a name being typed sits exactly where it will once created', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Test 49');
    await tester.pumpAndSettle();

    final draftPill = pillOf(tester, draftField());
    final typed = tester.getRect(find.byType(EditableText));
    final typedOffset = typed.center.dy - draftPill.center.dy;
    final typedTop = typed.top - draftPill.top;

    // Create it, reopen, and measure the same name as a settled label.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await reopenMenu(tester);

    final label = find.descendant(
      of: find.byType(SondrSwipeRow),
      matching: find.text('Test 49'),
    );
    expect(label, findsOneWidget);
    final labelPill = pillOf(tester, label);
    final labelRect = tester.getRect(label);

    expect(
      typedOffset,
      closeTo(labelRect.center.dy - labelPill.center.dy, 0.5),
      reason: 'typed text is not where the label lands',
    );
    expect(
      typedTop,
      closeTo(labelRect.top - labelPill.top, 0.5),
      reason: 'typed text and the label do not share a baseline',
    );
    // And the two boxes are the same height — same style, same strut.
    expect(typed.height, closeTo(labelRect.height, 0.5));
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
