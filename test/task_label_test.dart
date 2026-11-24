import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/features/timer/widgets/task_dropdown.dart';

/// Home's task label: the name alone, no arrow, where it always was.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_Tasks()),
          sessionStoreProvider.overrideWithValue(_NoStore()),
          liveActivityProvider.overrideWithValue(_SilentCard()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const TimerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(TimerScreen)));
  }

  testWidgets('no task chosen: "Tasks", and no arrow', (tester) async {
    await pump(tester);
    expect(find.text(kAllTasksLabel), findsOneWidget);
    expect(kAllTasksLabel, 'Tasks');
    expect(find.text('Task'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  // Measured on Development before the arrow went: the label's top, by
  // text size, is the same with a task chosen and without.
  for (final (ts, top) in [(0.824, 106.04225352112675), (1.0, 105.04225352112675), (1.235, 105.04225352112675)]) {
    testWidgets('at textScaler $ts it stands where it did, centred on the page', (tester) async {
      final c = await pump(tester, textScale: ts);
      final all = tester.getRect(find.text('Tasks'));
      expect(all.top, closeTo(top, 0.01));
      expect(all.center.dx, closeTo(390 / 2, 0.01));
      c.read(selectedTaskIdProvider.notifier).select('a');
      await tester.pumpAndSettle();
      final one = tester.getRect(find.text('Spanish'));
      expect(one.top, closeTo(top, 0.01));
      expect(one.center.dx, closeTo(390 / 2, 0.01));
    });
  }

  testWidgets('a tap opens the menu; a double-tap goes back to all tasks', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Add task'), findsOneWidget);
    await tester.tapAt(const Offset(195, 820));
    await tester.pumpAndSettle();

    c.read(selectedTaskIdProvider.notifier).select('a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spanish'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Spanish'));
    await tester.pumpAndSettle();
    expect(c.read(selectedTaskIdProvider), isNull);
    expect(find.text('Tasks'), findsOneWidget);
  });

  testWidgets('during a session: the name at full strength, and out of reach', (tester) async {
    final c = await pump(tester);
    c.read(selectedTaskIdProvider.notifier).select('a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.ancestor(of: find.text('Spanish'), matching: find.byType(Opacity)),
      findsNothing,
      reason: 'no dimming',
    );
    await tester.tap(find.text('Spanish'));
    await tester.pumpAndSettle();
    expect(find.text('Add task'), findsNothing, reason: 'locked');
    await tester.tap(find.text('Spanish'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Spanish'));
    await tester.pumpAndSettle();
    expect(c.read(selectedTaskIdProvider), 'a', reason: 'locked');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Tasks implements TasksRepository {
  @override
  Future<List<Task>> fetchAll() async => const [Task(id: 'a', name: 'Spanish')];
  @override
  Future<void> save(Task task) async {}
  @override
  Future<void> rename(String taskId, String name) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
}

class _NoStore implements SessionStore {
  SessionClock? saved;
  @override
  Future<SessionClock?> read() async => saved;
  @override
  Future<void> write(SessionClock clock) async => saved = clock;
  @override
  Future<void> clear() async => saved = null;
}

class _SilentCard implements LiveActivity {
  @override
  Stream<String> get links => const Stream<String>.empty();
  @override
  Future<void> show(SessionClock clock) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> ready() async {}
}
