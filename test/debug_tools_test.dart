import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/debug_flags.dart';
import 'package:sondr/core/debug_tools.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_screen.dart';

/// The debug tools show for the listed test account alone, in a
/// DEBUG_TOOLS build — and go the moment that account signs out.
void main() {
  group('the rule', () {
    test('a listed account in a DEBUG_TOOLS build, and nobody else', () {
      expect(kDebugUids, isNotEmpty);
      expect(kDebugUids.every((u) => u.length == 28), isTrue, reason: 'Firebase uids');
      expect(debugToolsFor(kDebugUids.first, build: true), isTrue);
      expect(debugToolsFor('someone-else', build: true), isFalse);
      expect(debugToolsFor(null, build: true), isFalse, reason: 'a guest');
      expect(debugToolsFor(kDebugUids.first, build: false), isFalse, reason: 'a release build');
    });

    test('without the define — every normal build, and these tests — nothing shows for anyone', () {
      expect(kDebugTools, isFalse);
      expect(debugToolsFor(kDebugUids.first), isFalse);
    });
  });

  group('on Home', () {
    Future<void> pump(WidgetTester tester, _Uid uid) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _uidProvider.overrideWith(() => uid),
            currentUidProvider.overrideWith((ref) => ref.watch(_uidProvider)),
            // The rule as a DEBUG_TOOLS build has it, over the test's account.
            debugToolsProvider.overrideWith((ref) => debugToolsFor(ref.watch(currentUidProvider), build: true)),
            tasksRepositoryProvider.overrideWithValue(_FakeTasks([Task(id: 't', name: 'Golf', secondsByDay: const {})])),
            sessionStoreProvider.overrideWithValue(_NoStore()),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const TimerScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // The primer is for one task: choose it, as a tap on the dial would.
      ProviderScope.containerOf(tester.element(find.byType(TimerScreen))).read(selectedTaskIdProvider.notifier).select('t');
      await tester.pumpAndSettle();
    }

    testWidgets('the primer shows for the test account, and goes the moment it signs out', (tester) async {
      final uid = _Uid(kDebugUids.first);
      await pump(tester, uid);
      expect(find.textContaining('DEBUG'), findsOneWidget);
      uid.set(null);
      await tester.pump();
      expect(find.textContaining('DEBUG'), findsNothing, reason: 'gone on the very next frame');
      await tester.pumpAndSettle();
      expect(find.textContaining('DEBUG'), findsNothing);
    });

    testWidgets('any other account sees no primer', (tester) async {
      await pump(tester, _Uid('a-founder'));
      expect(find.textContaining('DEBUG'), findsNothing);
    });
  });
}

class _Uid extends Notifier<String?> {
  _Uid(this.initial);
  final String? initial;
  @override
  String? build() => initial;
  void set(String? uid) => state = uid;
}

final _uidProvider = NotifierProvider<_Uid, String?>(() => _Uid(null));

class _FakeTasks implements TasksRepository {
  _FakeTasks(this.tasks);
  final List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
  @override
  Future<void> save(Task task) async {}
  @override
  Future<void> delete(String taskId) async {}
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
