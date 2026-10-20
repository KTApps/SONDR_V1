import SwiftUI

/// Whether the card is still counting toward a milestone, is inside the last
/// minute of it, or has reached it.
///
/// One decision made in one place, because the bug it fixes came from the
/// views each assuming the milestone was still ahead. A running card hands
/// its countdown to the system as a date and is then left alone for hours;
/// `Text(_, style: .relative)` does not stop at zero, it turns round and
/// counts back **up** — "1 sec, 2 sec, 3 sec".
///
/// There is no staleDate and no timeline anywhere in this: a stale card
/// loses the seconds off its elapsed clock, and `TimelineView` schedules
/// are not honoured in a Live Activity (both measured on device). The card
/// changes only when the app pushes it, so the states below are decided at
/// push time and hold until the next push.
///
/// Four views need the answer — the Lock Screen line, the Lock Screen ring,
/// and the ring in each island presentation — and all four must agree.
enum MilestoneDisplay: Equatable {
  /// More than a minute to go: a live countdown.
  case counting(remaining: TimeInterval)

  /// Inside the last minute: a fixed line, so the countdown cannot run
  /// past zero before the next push. The ring is unchanged.
  case lastMinute

  /// Reached. The ring is complete and the line says so.
  case crossed

  static let lastMinuteMessage = "<1 min to your next milestone"
  static let reachedMessage = "You've reached a milestone"

  /// Decided from the session alone, at `now` — which, with no staleness
  /// and no timeline, is the moment of the push that drew this card.
  static func state(for session: SessionSnapshot, at now: Date) -> MilestoneDisplay {
    let remaining = session.projectedRemaining(at: now)
    if remaining <= 0 { return .crossed }
    if remaining <= SessionSnapshot.lastMinuteSeconds { return .lastMinute }
    return .counting(remaining: remaining)
  }

  var isCrossed: Bool { self == .crossed }

  /// What the ring is drawn in.
  ///
  /// A reached milestone takes the colour the app gives a completed ring —
  /// `ringFillOuter`, #FAFAFA in `lib/core/theme/greyscale_tokens.dart`.
  /// Anything short of it keeps the ordinary fill.
  var ringFill: Color { isCrossed ? Ink.ringComplete : Ink.ringFill }
}
