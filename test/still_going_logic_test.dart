import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/timer/session_clock.dart';

/// A session left running overnight counts the night, because the clock is
/// the wall's. These are the rules that catch it.
void main() {
  final t0 = DateTime(2026, 10, 18, 9);
  DateTime at(Duration d) => t0.add(d);
  DateTime hours(num h) => at(Duration(minutes: (h * 60).round()));

  group('when to ask', () {
    test('three hours running is the threshold, and not a minute before', () {
      final clock = SessionClock(startedAt: t0);
      expect(clock.shouldAsk(hours(2)), isFalse);
      expect(clock.shouldAsk(at(const Duration(hours: 2, minutes: 59))), isFalse);
      expect(
        clock.shouldAsk(at(const Duration(hours: 2, minutes: 59, seconds: 59))),
        isFalse,
      );
      expect(clock.shouldAsk(hours(3)), isTrue);
      expect(clock.shouldAsk(hours(9)), isTrue);
    });

    test('a paused session never asks, however long it has sat', () {
      // Paused BEFORE the threshold: elapsed freezes under it anyway.
      final early = SessionClock(startedAt: t0).pause(hours(1));
      expect(early.shouldAsk(hours(12)), isFalse);

      // Paused AFTER it — elapsed reads four hours and stays there. This is
      // the case the guard exists for: without it, a session deliberately
      // parked would be challenged every time the app was opened.
      final late = SessionClock(startedAt: t0).pause(hours(4));
      expect(late.elapsedAt(hours(12)), const Duration(hours: 4));
      expect(late.shouldAsk(hours(12)), isFalse);

      // And asks again once it is running.
      expect(early.resume(hours(12)).shouldAsk(hours(15)), isTrue);
      expect(late.resume(hours(12)).shouldAsk(hours(12)), isTrue);
    });

    test('paused time does not count toward the threshold', () {
      // Two hours worked either side of a six-hour pause: not three hours.
      final clock = SessionClock(startedAt: t0)
          .pause(hours(1))
          .resume(hours(7));
      expect(clock.elapsedAt(hours(8)), const Duration(hours: 2));
      expect(clock.shouldAsk(hours(8)), isFalse);
      expect(clock.shouldAsk(hours(9)), isTrue);
    });
  });

  group('after "Keep going"', () {
    test('it does not ask again until three hours further on', () {
      var clock = SessionClock(startedAt: t0);
      expect(clock.shouldAsk(hours(3)), isTrue);

      clock = clock.confirmedNow(hours(3));
      expect(clock.confirmedAt, const Duration(hours: 3));
      expect(clock.shouldAsk(hours(3)), isFalse);
      expect(clock.shouldAsk(hours(5)), isFalse);
      expect(
        clock.shouldAsk(at(const Duration(hours: 5, minutes: 59))),
        isFalse,
      );
      expect(clock.shouldAsk(hours(6)), isTrue);
    });

    test('confirming twice moves the mark each time', () {
      var clock = SessionClock(startedAt: t0).confirmedNow(hours(3));
      clock = clock.confirmedNow(hours(6));
      expect(clock.shouldAsk(hours(8)), isFalse);
      expect(clock.shouldAsk(hours(9)), isTrue);
    });

    test('the confirmation survives a relaunch', () {
      final clock = SessionClock(startedAt: t0).confirmedNow(hours(3));
      final back = SessionClock.decode(clock.encode())!;
      expect(back.confirmedAt, const Duration(hours: 3));
      expect(back.shouldAsk(hours(5)), isFalse);
      expect(back.shouldAsk(hours(6)), isTrue);
    });

    test('a session that has never been confirmed decodes as never asked', () {
      final back = SessionClock.decode(SessionClock(startedAt: t0).encode())!;
      expect(back.confirmedAt, Duration.zero);
      expect(back.shouldAsk(hours(3)), isTrue);
    });
  });

  group('logging until a corrected end time', () {
    test('it is the same arithmetic as elapsed', () {
      final clock = SessionClock(startedAt: t0);
      expect(clock.loggedUntil(hours(2)), const Duration(hours: 2));
      expect(clock.loggedUntil(hours(2)), clock.elapsedAt(hours(2)));
    });

    test('paused time comes off a corrected end too', () {
      // Worked 9–10, paused 10–11, resumed, and really stopped at 12 —
      // but the timer ran until 18:00.
      final clock = SessionClock(startedAt: t0)
          .pause(hours(1))
          .resume(hours(2));
      expect(clock.elapsedAt(hours(9)), const Duration(hours: 8));
      expect(clock.loggedUntil(hours(3)), const Duration(hours: 2));
    });

    test('an end inside an open pause stops at the pause', () {
      final clock = SessionClock(startedAt: t0).pause(hours(2));
      // Still paused at 18:00; ending "now" logs the two hours worked.
      expect(clock.loggedUntil(hours(9)), const Duration(hours: 2));
    });

    test('an end before the start is nothing, not a negative', () {
      expect(
        SessionClock(startedAt: hours(2)).loggedUntil(t0),
        Duration.zero,
      );
    });
  });
}
