import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/presence/friends_in_session.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

/// "4 friends are in a session", under the countdown on Home: shown only in
/// a session and only when any are, 22 below the countdown, and never
/// moving anything else.
void main() {
  final today = DayKey.of(DateTime.now());
  late DateTime now;
  late ProviderContainer c;

  Future<void> pump(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nowProvider.overrideWithValue(() => now),
          tasksRepositoryProvider.overrideWithValue(
            _Tasks([Task(id: 'a', name: 'Spanish', secondsByDay: {today: 2 * 3600 + 15 * 60})]),
          ),
          sessionStoreProvider.overrideWithValue(_NoStore()),
          liveActivityProvider.overrideWithValue(_SilentCard()),
          friendsInSessionProvider.overrideWith(_Count.new),
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
    c = ProviderScope.containerOf(tester.element(find.byType(TimerScreen)));
    c.read(selectedTaskIdProvider.notifier).select('a');
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester, [Duration by = const Duration(seconds: 8)]) async {
    now = now.add(by);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> friendsAre(WidgetTester tester, int n) async {
    (c.read(friendsInSessionProvider.notifier) as _Count).set(n);
    await settle(tester, const Duration(seconds: 1));
  }

  Finder line() => find.byKey(kHomeFriendsKey);
  AnimatedOpacity fadeOf(WidgetTester tester, Finder f) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: f, matching: find.byType(AnimatedOpacity)).first);
  String words(WidgetTester tester) => tester.widget<Text>(line()).data!;

  setUp(() => now = DateTime.now());

  testWidgets('idle: hidden whatever the count', (tester) async {
    await pump(tester);
    await friendsAre(tester, 3);
    expect(fadeOf(tester, line()).opacity, 0);
  });

  testWidgets('in a session: hidden at 0, "1 friend is", "N friends are", and fades out with its words', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await settle(tester);
    expect(fadeOf(tester, line()).opacity, 0, reason: 'nobody yet');

    await friendsAre(tester, 1);
    expect(words(tester), '1 friend is in a session');
    final fade = fadeOf(tester, line());
    expect(fade.opacity, 1);
    expect(fade.duration, kHomeSessionFade);
    expect(fade.duration, const Duration(milliseconds: 300));
    expect(fade.curve, Curves.easeOut);

    await friendsAre(tester, 4);
    expect(words(tester), '4 friends are in a session');
    expect(fadeOf(tester, line()).opacity, 1);

    await friendsAre(tester, 0);
    expect(fadeOf(tester, line()).opacity, 0);
    expect(words(tester), '4 friends are in a session', reason: 'fading out with its words');

    // Paused is still a session.
    await friendsAre(tester, 2);
    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(fadeOf(tester, line()).opacity, 1);

    // The session ends: gone, whatever the count.
    await c.read(timerControllerProvider.notifier).discard();
    await settle(tester);
    expect(fadeOf(tester, line()).opacity, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('22 under the countdown\'s line box, centred, supporting text in the quiet tone', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await settle(tester);
    await friendsAre(tester, 4);
    final countdown = tester.getRect(find.byKey(kHomeCountdownKey));
    final friends = tester.getRect(line());
    expect(friends.top - countdown.bottom, closeTo(22, 0.01));
    expect(friends.center.dx, closeTo(390 / 2, 0.01));
    final style = tester.widget<Text>(line()).style!;
    final body = Theme.of(tester.element(line())).textTheme.bodyMedium!;
    final countdownStyle = tester.widget<Text>(find.byKey(kHomeCountdownKey)).style!;
    expect(style.fontSize, 13, reason: 'Supporting text');
    expect(countdownStyle.fontSize, 14, reason: 'one step above it');
    expect(style.fontWeight, body.fontWeight);
    expect(style.color, GreyscaleTokens.of(tester.element(line())).textTertiary);
    expect(style.color, const Color(0xFF6E6E6E));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final ts in [0.824, 1.0, 1.235]) {
    testWidgets('at textScaler $ts the line moves nothing: everything else where it was with 0 and with 4', (tester) async {
      await pump(tester, textScale: ts);
      Map<String, Rect> layout() => {
        'heading': tester.getRect(find.text('Last 10 days')),
        'cta': tester.getRect(find.text('View your progress')),
        'countdown': tester.getRect(find.byKey(kHomeCountdownKey)),
        'dial': tester.getRect(find.byWidgetPredicate((w) => w is SegmentedDial && w.size > 100)),
        'stop': tester.getRect(find.text('Stop')),
      };
      await tester.tap(find.text('Start'));
      await settle(tester);
      final none = layout();
      await friendsAre(tester, 4);
      final four = layout();
      expect(four, none);
      expect(tester.getRect(line()).top - four['countdown']!.bottom, closeTo(22, 0.01));
      expect(tester.getRect(line()).center.dx, closeTo(390 / 2, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _Count extends FriendsInSession {
  @override
  int build() => 0;

  void set(int n) => state = n;
}

class _Tasks implements TasksRepository {
  _Tasks(this.tasks);
  List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<void> save(Task task) async =>
      tasks = [for (final t in tasks) t.id == task.id ? task : t];
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
