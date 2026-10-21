import SwiftUI
import XCTest

/// The card is redrawn only when the app pushes it, so what it says is
/// decided at push time and has to be right for as long as the push lasts.
/// Three states, and the boundaries between them are the whole point.
final class MilestoneDisplayTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
  private let hour: TimeInterval = 3600

  // MARK: - Counting

  func testCountingWhileMoreThanAMinuteRemains() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)
    let now = t0.addingTimeInterval(48 * 60)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: now),
      .counting(remaining: 3 * hour + 12 * 60)
    )
  }

  func testTheOrdinaryRingKeepsTheOrdinaryFill() {
    XCTAssertEqual(MilestoneDisplay.counting(remaining: hour).ringFill, Ink.ringFill)
    XCTAssertEqual(MilestoneDisplay.lastMinute.ringFill, Ink.ringFill)
  }

  func testAPausedSessionShortOfTheMilestoneIsStillCounting() {
    let pausedAt = t0.addingTimeInterval(30 * 60)
    let session = SessionSnapshot(startedAt: t0, pausedAt: pausedAt, taskSecondsBefore: 16 * hour)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: pausedAt.addingTimeInterval(4 * hour)),
      .counting(remaining: 3.5 * hour),
      "a pause freezes the countdown; it does not advance it"
    )
  }

  // MARK: - The last minute

  func testPushedWithSixtySecondsLeftIsTheLastMinute() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: t0.addingTimeInterval(hour - 60)),
      .lastMinute
    )
  }

  func testPushedWithSixtyOneSecondsLeftIsStillCounting() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: t0.addingTimeInterval(hour - 61)),
      .counting(remaining: 61)
    )
  }

  func testPushedWithOneSecondLeftIsTheLastMinute() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: t0.addingTimeInterval(hour - 1)),
      .lastMinute
    )
  }

  func testTheLastMinuteLine() {
    XCTAssertEqual(MilestoneDisplay.lastMinuteMessage, "<1 min to your next milestone")
  }

  // MARK: - Crossed

  func testTheInstantOfTheCrossingIsCrossed() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(MilestoneDisplay.state(for: session, at: t0.addingTimeInterval(hour)), .crossed)
  }

  func testPausedAfterCrossingIsCrossed() {
    let pausedAt = t0.addingTimeInterval(90 * 60)
    let session = SessionSnapshot(startedAt: t0, pausedAt: pausedAt, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(MilestoneDisplay.state(for: session, at: pausedAt), .crossed)
  }

  func testResumedAfterCrossingIsCrossed() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(MilestoneDisplay.state(for: session, at: t0.addingTimeInterval(90 * 60)), .crossed)
  }

  func testASecondCrossingInOneSessionLooksTheSame() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(MilestoneDisplay.state(for: session, at: t0.addingTimeInterval(21.5 * hour)), .crossed)
  }

  func testTheCrossedRingIsTheCompletedColour() {
    XCTAssertEqual(MilestoneDisplay.crossed.ringFill, Ink.ringComplete)
    XCTAssertNotEqual(
      MilestoneDisplay.crossed.ringFill,
      Ink.ringFill,
      "a complete ring in the ordinary grey is indistinguishable from an unfinished one"
    )
  }

  func testTheCrossedLine() {
    XCTAssertEqual(MilestoneDisplay.reachedMessage, "You've reached a milestone")
  }

  // MARK: - And out the other side

  func testAFreshSessionAfterAStopIsCountingAgain() {
    let next = SessionSnapshot(startedAt: t0, taskSecondsBefore: 20.5 * hour)

    XCTAssertEqual(
      MilestoneDisplay.state(for: next, at: t0),
      .counting(remaining: 19.5 * hour),
      "a new session counts toward the next milestone, not the one already passed"
    )
  }
}
