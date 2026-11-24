import '../tasks/models/task.dart';

/// "… to your next milestone", as Home says it during a session.
///
/// The Lock Screen card says the same thing, and the two must not drift: the
/// wording is the card's paused wording (`MilestoneWording.remaining` in
/// `ios/SondrWidgets/MilestoneWording.swift`), the two fixed lines are
/// `MilestoneDisplay`'s, and the arithmetic is
/// `SessionSnapshot.projectedRemaining`. The tests in
/// `test/milestone_countdown_test.dart` repeat the Swift tests case for case,
/// so a change on either side fails the other's mirror.

/// Inside this many seconds of the crossing, the line stops counting.
/// `SessionSnapshot.lastMinuteSeconds`.
const int kMilestoneLastMinuteSeconds = 60;

/// `MilestoneDisplay.lastMinuteMessage`.
const String kMilestoneLastMinuteLine = '<1 min to your next milestone';

/// `MilestoneDisplay.reachedMessage`.
const String kMilestoneReachedLine = "You've reached a milestone";

const int _step = Task.milestoneStepHours * 3600;

/// The milestone this session set out to reach: the first one strictly above
/// where the task stood when it began. `SessionSnapshot.targetSeconds`.
int milestoneTargetSeconds(int taskSecondsBefore) =>
    (taskSecondsBefore ~/ _step) * _step + _step;

/// How long until the session reaches its target; negative once it has.
/// `SessionSnapshot.projectedRemaining`.
int projectedRemainingSeconds({
  required int taskSecondsBefore,
  required int sessionSeconds,
}) =>
    milestoneTargetSeconds(taskSecondsBefore) -
    (taskSecondsBefore + sessionSeconds);

/// "3 hrs, 8 min", "1 hr", "45 min", "1 min": hours and minutes, the
/// seconds dropped, never less than a minute. `MilestoneWording.remaining`,
/// which is the system formatter's short style — measured to truncate to the
/// minute, not round.
String milestoneRemainingWords(int seconds) {
  final s = seconds < 60 ? 60 : seconds;
  final hours = s ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  return [
    if (hours > 0) '$hours ${hours == 1 ? 'hr' : 'hrs'}',
    if (minutes > 0) '$minutes min',
  ].join(', ');
}

/// The whole line for a session [sessionSeconds] long on a task that had
/// [taskSecondsBefore] when it began. `MilestoneDisplay.state`, worded.
String milestoneCountdownLine({
  required int taskSecondsBefore,
  required int sessionSeconds,
}) {
  final remaining = projectedRemainingSeconds(
    taskSecondsBefore: taskSecondsBefore,
    sessionSeconds: sessionSeconds,
  );
  if (remaining <= 0) return kMilestoneReachedLine;
  if (remaining <= kMilestoneLastMinuteSeconds) return kMilestoneLastMinuteLine;
  return '${milestoneRemainingWords(remaining)} to your next milestone';
}
