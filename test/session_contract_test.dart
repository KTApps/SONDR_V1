import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/timer/session_clock.dart';

/// The session JSON is read by two languages.
///
/// Dart writes it into the App Group; the Live Activity's Swift reads it
/// there, in another process, with no way to ask a question. The field names
/// and units below are the whole agreement — SessionSnapshot.swift mirrors
/// this file test for test.
void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1760000000000);

  Map<String, dynamic> encoded(SessionClock clock) =>
      jsonDecode(clock.encode()) as Map<String, dynamic>;

  test('a running session writes milliseconds and omits what is absent', () {
    final map = encoded(SessionClock(startedAt: t0));

    expect(map['startedAt'], 1760000000000);
    expect(map['pausedMs'], 0);
    expect(map.containsKey('pausedAt'), isFalse, reason: 'running');
    expect(map.containsKey('taskId'), isFalse);
    expect(map.containsKey('taskName'), isFalse);
    expect(map.containsKey('taskSecondsBefore'), isFalse);
    expect(map.containsKey('confirmedMs'), isFalse);
  });

  test('a full session writes every agreed field', () {
    final map = encoded(
      SessionClock(
        startedAt: t0,
        pausedTotal: const Duration(minutes: 2),
        pausedAt: t0.add(const Duration(minutes: 30)),
        taskId: 'task-7',
        taskName: 'Learn piano',
        taskSecondsBefore: 68400,
        confirmedAt: const Duration(hours: 3),
      ),
    );

    expect(map, {
      'startedAt': 1760000000000,
      'pausedMs': 120000,
      'pausedAt': t0.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      'taskId': 'task-7',
      'taskName': 'Learn piano',
      'taskSecondsBefore': 68400,
      'confirmedMs': 10800000,
    }, reason: 'the Swift side decodes exactly these keys');
  });

  test('what is written comes back', () {
    final before = SessionClock(
      startedAt: t0,
      pausedTotal: const Duration(minutes: 2),
      pausedAt: t0.add(const Duration(minutes: 30)),
      taskId: 'task-7',
      taskName: 'Learn piano',
      taskSecondsBefore: 68400,
      confirmedAt: const Duration(hours: 3),
    );

    final after = SessionClock.decode(before.encode())!;

    expect(after.startedAt, before.startedAt);
    expect(after.pausedTotal, before.pausedTotal);
    expect(after.pausedAt, before.pausedAt);
    expect(after.taskId, before.taskId);
    expect(after.taskName, before.taskName);
    expect(after.taskSecondsBefore, before.taskSecondsBefore);
    expect(after.confirmedAt, before.confirmedAt);
  });

  test('a session written by the build before this one still reads', () {
    // No taskName, no taskSecondsBefore — the shape shipped in build 46.
    final old = jsonEncode({
      'startedAt': 1760000000000,
      'pausedMs': 0,
      'taskId': 'task-7',
    });

    final clock = SessionClock.decode(old)!;

    expect(clock.taskName, isNull);
    expect(clock.taskSecondsBefore, 0, reason: 'absent means none logged yet');
    expect(clock.taskId, 'task-7');
  });

  group('pausing keeps the rest of the session', () {
    final full = SessionClock(
      startedAt: t0,
      taskId: 'task-7',
      taskName: 'Learn piano',
      taskSecondsBefore: 68400,
      confirmedAt: const Duration(hours: 3),
    );

    test('pause carries the task and the confirmation', () {
      final paused = full.pause(t0.add(const Duration(hours: 3)));

      expect(paused.taskName, 'Learn piano');
      expect(paused.taskSecondsBefore, 68400);
      expect(paused.confirmedAt, const Duration(hours: 3));
    });

    test('resuming does not make it ask "Still going?" again', () {
      final paused = full.pause(t0.add(const Duration(hours: 3)));
      final back = paused.resume(t0.add(const Duration(hours: 3, minutes: 5)));

      expect(back.confirmedAt, const Duration(hours: 3));
      expect(
        back.shouldAsk(t0.add(const Duration(hours: 3, minutes: 6))),
        isFalse,
        reason: 'the pause dropped the confirmation, so it asks straight away',
      );
      expect(
        back.shouldAsk(t0.add(const Duration(hours: 6, minutes: 6))),
        isTrue,
        reason: 'it must still ask again three hours later',
      );
    });

    test('resuming carries the task through', () {
      final back = full
          .pause(t0.add(const Duration(hours: 1)))
          .resume(t0.add(const Duration(hours: 2)));

      expect(back.taskName, 'Learn piano');
      expect(back.taskSecondsBefore, 68400);
    });
  });

  group('the fixtures both languages read', () {
    // test/fixtures/sessions.json is loaded by this file and by
    // ios/RunnerTests/SharedFixtureTests.swift. Same bytes, same answer —
    // or the Lock Screen is lying about how long someone has worked.
    final fixtures =
        jsonDecode(File('test/fixtures/sessions.json').readAsStringSync())
            as Map<String, dynamic>;
    final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();

    test('there are cases to check', () {
      expect(cases, isNotEmpty);
    });

    for (final c in cases) {
      test('elapsed: ${c['name']}', () {
        final clock = SessionClock.fromMap(
          Map<String, dynamic>.from(c['session'] as Map),
        )!;
        final now = DateTime.fromMillisecondsSinceEpoch(c['nowMs'] as int);

        expect(
          clock.elapsedAt(now).inMilliseconds,
          c['elapsedMs'],
          reason: 'Dart and Swift disagree about this session',
        );
      });
    }
  });
}
