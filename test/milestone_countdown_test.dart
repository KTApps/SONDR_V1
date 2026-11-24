import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/timer/milestone_countdown.dart';

/// Home's milestone line, mirroring the Swift tests case for case — same
/// inputs, same strings — so the app and the Lock Screen card cannot drift.
///
/// ios/RunnerTests/MilestoneWordingTests.swift,
/// ios/RunnerTests/MilestoneDisplayTests.swift and the target cases of
/// ios/RunnerTests/SessionSnapshotTests.swift.
void main() {
  const hour = 3600;

  String line(int before, int session) =>
      milestoneCountdownLine(taskSecondsBefore: before, sessionSeconds: session);
  int remaining(int before, int session) =>
      projectedRemainingSeconds(taskSecondsBefore: before, sessionSeconds: session);

  group('MilestoneWordingTests', () {
    test('testHoursAndMinutes', () {
      expect(milestoneRemainingWords(3 * hour + 8 * 60), '3 hrs, 8 min');
    });

    test('testAWholeHourDropsTheMinutes', () {
      expect(milestoneRemainingWords(hour), '1 hr');
    });

    test('testMinutesAlone', () {
      expect(milestoneRemainingWords(45 * 60), '45 min');
    });

    test('testOneMinute', () {
      expect(milestoneRemainingWords(60), '1 min');
    });

    test('testLessThanAMinuteIsStillAMinute', () {
      expect(milestoneRemainingWords(12), '1 min');
      expect(milestoneRemainingWords(0), '1 min');
    });

    test('testSecondsNeverAppear', () {
      expect(milestoneRemainingWords(3 * hour + 8 * 60 + 29), '3 hrs, 8 min');
    });

    test('testATwentyHourBandAtItsFullest', () {
      expect(milestoneRemainingWords(20 * hour), '20 hrs');
    });

    // Measured off the system formatter the Swift side uses: it truncates
    // to the minute rather than rounding.
    test('the formatter truncates, as measured', () {
      expect(milestoneRemainingWords(3 * hour + 8 * 60 + 30), '3 hrs, 8 min');
      expect(milestoneRemainingWords(2 * hour - 1), '1 hr, 59 min');
      expect(milestoneRemainingWords(20 * hour - 1), '19 hrs, 59 min');
      expect(milestoneRemainingWords(119), '1 min');
    });
  });

  group('MilestoneDisplayTests', () {
    test('testCountingWhileMoreThanAMinuteRemains', () {
      expect(remaining(16 * hour, 48 * 60), 3 * hour + 12 * 60);
      expect(line(16 * hour, 48 * 60), '3 hrs, 12 min to your next milestone');
    });

    test('testAPausedSessionShortOfTheMilestoneIsStillCounting', () {
      // Paused 30 minutes in: the figure is the session as it stood.
      expect(remaining(16 * hour, 30 * 60), (3.5 * hour).round());
      expect(line(16 * hour, 30 * 60), '3 hrs, 30 min to your next milestone');
    });

    test('testPushedWithSixtySecondsLeftIsTheLastMinute', () {
      expect(line(19 * hour, hour - 60), kMilestoneLastMinuteLine);
    });

    test('testPushedWithSixtyOneSecondsLeftIsStillCounting', () {
      expect(remaining(19 * hour, hour - 61), 61);
      expect(line(19 * hour, hour - 61), '1 min to your next milestone');
    });

    test('testPushedWithOneSecondLeftIsTheLastMinute', () {
      expect(line(19 * hour, hour - 1), kMilestoneLastMinuteLine);
    });

    test('testTheLastMinuteLine', () {
      expect(kMilestoneLastMinuteLine, '<1 min to your next milestone');
    });

    test('testTheInstantOfTheCrossingIsCrossed', () {
      expect(line(19 * hour, hour), kMilestoneReachedLine);
    });

    test('testPausedAfterCrossingIsCrossed', () {
      expect(line(19 * hour, 90 * 60), kMilestoneReachedLine);
    });

    test('testResumedAfterCrossingIsCrossed', () {
      expect(line(19 * hour, 90 * 60), kMilestoneReachedLine);
    });

    test('testASecondCrossingInOneSessionLooksTheSame', () {
      expect(line(19 * hour, (21.5 * hour).round()), kMilestoneReachedLine);
    });

    test('testTheCrossedLine', () {
      expect(kMilestoneReachedLine, "You've reached a milestone");
    });

    test('testAFreshSessionAfterAStopIsCountingAgain', () {
      final before = (20.5 * hour).round();
      expect(remaining(before, 0), (19.5 * hour).round());
      expect(line(before, 0), '19 hrs, 30 min to your next milestone');
    });
  });

  group('SessionSnapshotTests targets', () {
    test('testTheTargetIsTheFirstMilestoneAboveWhereTheTaskStood', () {
      expect(milestoneTargetSeconds(7 * hour), 20 * hour);
      expect(milestoneTargetSeconds(31 * hour), 40 * hour);
    });

    test('testATaskOnAnExactMilestoneAimsAtTheNextOne', () {
      expect(milestoneTargetSeconds(20 * hour), 40 * hour);
    });

    test('testProjectedRemainingGoesNegativeOnceCrossedWhileRemainingResets', () {
      expect(remaining(19 * hour, 90 * 60), -30 * 60);
    });

    test('testProjectedRemainingKeepsFallingThroughASecondMilestone', () {
      expect(remaining(19 * hour, (21.5 * hour).round()), lessThan(0));
    });

    test('testAFreshSessionAfterAStopCountsDownFromTheNewRemaining', () {
      final before = (20.5 * hour).round();
      expect(milestoneTargetSeconds(before), 40 * hour);
      expect(remaining(before, 0), (19.5 * hour).round());
    });
  });

  test('the spec\'s own example', () {
    expect(line(0, 5 * 60), '19 hrs, 55 min to your next milestone');
  });
}
