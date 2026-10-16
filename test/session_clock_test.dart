import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/timer/session_clock.dart';

/// Time passes whether or not the app is awake.
void main() {
  final t0 = DateTime(2026, 10, 15, 9);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  test('elapsed is the wall clock, with no ticking required', () {
    final clock = SessionClock(startedAt: t0);
    expect(clock.elapsedAt(t0), Duration.zero);
    expect(
      clock.elapsedAt(t0.add(const Duration(hours: 2))),
      const Duration(hours: 2),
    );
  });

  test('a pause stops the answer moving, and is not counted', () {
    var clock = SessionClock(startedAt: at(0));
    clock = clock.pause(at(10));
    // Ten minutes of work, then nothing however long the pause lasts.
    expect(clock.elapsedAt(at(10)), const Duration(minutes: 10));
    expect(clock.elapsedAt(at(40)), const Duration(minutes: 10));

    clock = clock.resume(at(40));
    expect(clock.elapsedAt(at(40)), const Duration(minutes: 10));
    expect(clock.elapsedAt(at(50)), const Duration(minutes: 20));
    expect(clock.pausedTotal, const Duration(minutes: 30));
  });

  test('several pauses all come off', () {
    var clock = SessionClock(startedAt: at(0));
    clock = clock.pause(at(5)).resume(at(15));
    clock = clock.pause(at(20)).resume(at(50));
    // 5 + 5 worked, 10 + 30 paused.
    expect(clock.elapsedAt(at(50)), const Duration(minutes: 10));
    expect(clock.elapsedAt(at(60)), const Duration(minutes: 20));
  });

  test('pausing twice is not a way to lose time', () {
    final clock = SessionClock(startedAt: at(0)).pause(at(10));
    expect(clock.pause(at(30)).elapsedAt(at(30)), const Duration(minutes: 10));
  });

  test('a clock moved backwards never yields a negative session', () {
    final clock = SessionClock(startedAt: at(10));
    expect(clock.elapsedAt(at(0)), Duration.zero);
  });

  group('round trip', () {
    test('a running session survives encoding', () {
      final clock = SessionClock(
        startedAt: at(0),
        pausedTotal: const Duration(minutes: 3),
        taskId: 'task-1',
      );
      final back = SessionClock.decode(clock.encode())!;
      expect(back.startedAt, clock.startedAt);
      expect(back.pausedTotal, clock.pausedTotal);
      expect(back.taskId, 'task-1');
      expect(back.isPaused, isFalse);
      expect(back.elapsedAt(at(30)), clock.elapsedAt(at(30)));
    });

    test('a paused session survives encoding', () {
      final clock = SessionClock(startedAt: at(0)).pause(at(8));
      final back = SessionClock.decode(clock.encode())!;
      expect(back.isPaused, isTrue);
      expect(back.elapsedAt(at(99)), const Duration(minutes: 8));
    });

    test('nonsense decodes to nothing rather than throwing', () {
      expect(SessionClock.decode(null), isNull);
      expect(SessionClock.decode(''), isNull);
      expect(SessionClock.decode('not json'), isNull);
      expect(SessionClock.decode('{"nope":1}'), isNull);
      expect(SessionClock.decode('[1,2,3]'), isNull);
    });
  });
}
