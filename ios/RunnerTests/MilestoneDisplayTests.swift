import SwiftUI
import XCTest

/// The card has to know it has crossed a milestone without anything waking
/// up to tell it. Three different routes say so and all three are here,
/// because missing any one of them puts the old bug back: a relative
/// countdown that runs past zero and starts counting up.
final class MilestoneDisplayTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
  private let hour: TimeInterval = 3600

  // MARK: - Still counting

  func testCountingWhileTheMilestoneIsStillAhead() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)
    let now = t0.addingTimeInterval(48 * 60)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: now, isStale: false),
      .counting(remaining: 3 * hour + 12 * 60)
    )
  }

  func testTheOrdinaryRingKeepsTheOrdinaryFill() {
    let display = MilestoneDisplay.counting(remaining: hour)

    XCTAssertEqual(display.ringFill, Ink.ringFill)
    XCTAssertNotEqual(display.ringFill, Ink.ringComplete)
  }

  func testAPausedSessionShortOfTheMilestoneIsStillCounting() {
    let pausedAt = t0.addingTimeInterval(30 * 60)
    let session = SessionSnapshot(
      startedAt: t0,
      pausedAt: pausedAt,
      taskSecondsBefore: 16 * hour
    )

    XCTAssertEqual(
      MilestoneDisplay.state(
        for: session,
        at: pausedAt.addingTimeInterval(4 * hour),
        isStale: false
      ),
      .counting(remaining: 3.5 * hour),
      "a pause freezes the countdown; it does not advance it"
    )
  }

  // MARK: - Crossed, by each of the three routes

  func testStaleMeansCrossedEvenWhileTheArithmeticStillSaysAhead() {
    // The system redrew with isStale set. Whatever the frozen state says,
    // the staleDate it was given has passed.
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)
    let now = t0.addingTimeInterval(48 * 60)

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: now, isStale: true),
      .crossed
    )
  }

  func testPausedAfterCrossingIsCrossed() {
    // Paused at 20h30m on a task that stood at 19h. No staleDate was ever
    // set for this push, so isStale can never become true — the arithmetic
    // is the only thing that can catch it.
    let pausedAt = t0.addingTimeInterval(90 * 60)
    let session = SessionSnapshot(
      startedAt: t0,
      pausedAt: pausedAt,
      taskSecondsBefore: 19 * hour
    )

    XCTAssertNil(session.staleDate(at: pausedAt))
    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: pausedAt, isStale: false),
      .crossed
    )
  }

  func testResumedAfterCrossingIsCrossed() {
    // Resumed past the crossing: the fresh staleDate is already in the
    // past, and the system has not yet redrawn, so isStale is still false.
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)
    let now = t0.addingTimeInterval(90 * 60)

    XCTAssertLessThan(session.staleDate(at: now)!, now)
    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: now, isStale: false),
      .crossed
    )
  }

  func testTheInstantOfTheCrossingCountsAsCrossed() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)
    let exactly = t0.addingTimeInterval(hour) // 20h on the nose

    XCTAssertEqual(session.projectedRemaining(at: exactly), 0, accuracy: 0.001)
    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: exactly, isStale: false),
      .crossed
    )
  }

  func testASecondCrossingInOneSessionLooksTheSame() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)
    let past = t0.addingTimeInterval(21.5 * hour) // 40h30m on the task

    XCTAssertEqual(
      MilestoneDisplay.state(for: session, at: past, isStale: false),
      .crossed
    )
  }

  // MARK: - What crossed looks like

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
    // The crossed session was stopped; its time, the crossed hours
    // included, is now part of the task.
    let next = SessionSnapshot(startedAt: t0, taskSecondsBefore: 20.5 * hour)

    XCTAssertEqual(
      MilestoneDisplay.state(for: next, at: t0, isStale: false),
      .counting(remaining: 19.5 * hour),
      "a new session counts toward the next milestone, not the one already passed"
    )
    XCTAssertEqual(
      MilestoneDisplay.state(for: next, at: t0, isStale: false).ringFill,
      Ink.ringFill
    )
  }
}
