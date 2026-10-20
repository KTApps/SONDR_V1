import SwiftUI

/// Whether the card is still counting toward a milestone, or has reached one.
///
/// This is one decision made in one place because the bug it fixes came from
/// the views each assuming the milestone was still ahead. A running card
/// hands its countdown to the system as a date and is then left alone for
/// hours; when that date passes, `Text(_, style: .relative)` does not stop at
/// zero, it turns round and counts back **up** — "1 sec, 2 sec, 3 sec".
///
/// Four views need the answer — the Lock Screen line, the Lock Screen ring,
/// and the ring in each island presentation — and all four must agree, or the
/// card says one thing and draws another.
enum MilestoneDisplay: Equatable {
  /// Still filling. How long is left, always positive.
  case counting(remaining: TimeInterval)

  /// Reached. The ring is complete and the line says so.
  case crossed

  /// The line under the clock when the milestone has been reached.
  static let reachedMessage = "You've reached a milestone"

  /// Two different questions, because neither answers on its own.
  ///
  /// `isStale` is the system's answer and the only one available when the
  /// app has not run since the crossing: the activity's `staleDate` is set
  /// to the projected crossing, and once it passes the system redraws with
  /// this set. Nothing has to wake up for it.
  ///
  /// The arithmetic is the other two answers, and the reason the staleDate
  /// alone is not enough. A session **paused** after crossing is pushed with
  /// no staleDate at all, so it can never go stale; a session **resumed**
  /// after crossing is pushed with a fresh one that is already in the past.
  /// In both the projected remaining has gone negative, and that is what
  /// catches them.
  static func state(
    for session: SessionSnapshot,
    at now: Date,
    isStale: Bool
  ) -> MilestoneDisplay {
    let remaining = session.projectedRemaining(at: now)
    if isStale || remaining <= 0 { return .crossed }
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
