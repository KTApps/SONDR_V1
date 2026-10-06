import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';

/// Guards the "rings build toward the next milestone" behaviour at the two
/// places it is drawn — the profile tiles and the dropdown pills. A unit test
/// on [Task] cannot catch a screen reading the wrong getter, which is exactly
/// the regression these cover.
void main() {
  final today = DateTime.now();

  Task taskOf(String name, int hours) => Task(
    id: name,
    name: name,
    secondsByDay: {
      '${today.year}-${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}': hours * 3600,
    },
  );

  Widget host(Widget child, List<Task> tasks) => ProviderScope(
    overrides: [tasksProvider.overrideWith(() => _StubTasks(tasks))],
    child: MaterialApp(
      theme: AppTheme.dark(),
      // The dropdown reads the task list only when opened, so something has
      // to have watched it first — as the timer screen does in the real app.
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(tasksProvider);
            return child;
          },
        ),
      ),
    ),
  );

  group('dropdown pills', () {
    testWidgets('a task past 20h does not render a full pill', (tester) async {
      // 47h is 2 milestones plus 7h — 0.35 through the third block, NOT full.
      await tester.pumpWidget(host(const TaskDropdown(), [taskOf('Golf', 47)]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TaskDropdown));
      await tester.pumpAndSettle();

      // The collapsed selector also shows the name, so scope to the open list.
      final pill = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(ClipRRect),
      );
      expect(pill, findsOneWidget);

      // The fill is the only Align inside the pill's clip — but the Align
      // itself fills the pill, so measure the sized box it holds.
      final align = find.descendant(of: pill, matching: find.byType(Align));
      expect(align, findsOneWidget);
      final fill = find.descendant(of: align, matching: find.byType(SizedBox));

      final pillWidth = tester.getSize(pill).width;
      final fillWidth = tester.getSize(fill.first).width;

      // Would be pillWidth if the pill had gone back to a clamped measure.
      expect(fillWidth, lessThan(pillWidth * 0.9));
      expect(fillWidth, greaterThan(0));
    });
  });

  // The profile tile's "of 20h" removal is not covered here: ProfileScreen
  // pulls in the account/Firebase providers and cannot be pumped without
  // scaffolding well beyond this change. Verified by inspection and on the
  // simulator instead. Extracting the tile into its own widget would make it
  // testable, and is worth doing when that screen is next touched.
}

class _StubTasks extends TasksController {
  _StubTasks(this._tasks);
  final List<Task> _tasks;

  @override
  Future<List<Task>> build() async => _tasks;
}
