import XCTest

/// The Swift half of the session contract.
///
/// Mirrors `test/session_contract_test.dart`: the same JSON, the same
/// arithmetic, checked on this side of the App Group. If these two files ever
/// disagree, the Lock Screen is lying about how long someone has worked.
final class SessionSnapshotTests: XCTestCase {
  /// 2025-10-09 08:53:20 UTC — the instant the Dart tests use.
  private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
  private let hour: TimeInterval = 3600

  private func json(_ fields: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: fields)
    return String(data: data, encoding: .utf8)!
  }

  // MARK: - Decoding

  func testDecodesEveryAgreedField() {
    let raw = json([
      "startedAt": 1_760_000_000_000,
      "pausedMs": 120_000,
      "pausedAt": 1_760_001_800_000,
      "taskId": "task-7",
      "taskName": "Learn piano",
      "taskSecondsBefore": 68_400,
      "confirmedMs": 10_800_000,
    ])

    let session = SessionSnapshot.decode(raw)

    XCTAssertEqual(session?.startedAt, t0)
    XCTAssertEqual(session?.pausedTotal, 120)
    XCTAssertEqual(session?.pausedAt, Date(timeIntervalSince1970: 1_760_001_800))
    XCTAssertEqual(session?.taskId, "task-7")
    XCTAssertEqual(session?.taskName, "Learn piano")
    XCTAssertEqual(session?.taskSecondsBefore, 68_400)
    XCTAssertEqual(session?.confirmedAt, 3 * 3600)
  }

  func testDecodesASessionFromTheBuildBeforeTheseFieldsExisted() {
    let session = SessionSnapshot.decode(
      json(["startedAt": 1_760_000_000_000, "pausedMs": 0, "taskId": "task-7"])
    )

    XCTAssertNotNil(session)
    XCTAssertNil(session?.taskName)
    XCTAssertEqual(session?.taskSecondsBefore, 0)
    XCTAssertFalse(session?.isPaused ?? true)
  }

  func testRefusesAnythingThatIsNotASession() {
    XCTAssertNil(SessionSnapshot.decode(nil))
    XCTAssertNil(SessionSnapshot.decode(""))
    XCTAssertNil(SessionSnapshot.decode("not json"))
    XCTAssertNil(SessionSnapshot.decode(json(["pausedMs": 0])))
    XCTAssertNil(SessionSnapshot.decode(json(["startedAt": "soon"])))
  }

  // MARK: - Elapsed

  func testElapsedCountsWallTimeLessPauses() {
    let session = SessionSnapshot(startedAt: t0, pausedTotal: 10 * 60)

    XCTAssertEqual(session.elapsed(at: t0.addingTimeInterval(hour)), 50 * 60)
  }

  func testAPausedSessionStopsCounting() {
    let session = SessionSnapshot(
      startedAt: t0,
      pausedAt: t0.addingTimeInterval(30 * 60)
    )

    XCTAssertEqual(session.elapsed(at: t0.addingTimeInterval(30 * 60)), 30 * 60)
    XCTAssertEqual(
      session.elapsed(at: t0.addingTimeInterval(5 * hour)),
      30 * 60,
      "five hours later a paused session has still run thirty minutes"
    )
  }

  func testAClockMovedBackwardsIsNotANegativeSession() {
    let session = SessionSnapshot(startedAt: t0)

    XCTAssertEqual(session.elapsed(at: t0.addingTimeInterval(-hour)), 0)
  }

  func testCountingFromIsTheInstantElapsedWasZero() {
    let session = SessionSnapshot(startedAt: t0, pausedTotal: 10 * 60)
    let now = t0.addingTimeInterval(hour)

    XCTAssertEqual(
      now.timeIntervalSince(session.countingFrom),
      session.elapsed(at: now),
      accuracy: 0.001,
      "the system subtracts these two on device; they must agree"
    )
  }

  // MARK: - Progress

  func testProgressOnATaskWithNoHistory() {
    let session = SessionSnapshot(startedAt: t0)

    XCTAssertEqual(session.progress(at: t0), 0)
    XCTAssertEqual(
      session.progress(at: t0.addingTimeInterval(10 * hour)),
      0.5,
      accuracy: 1e-9
    )
  }

  func testProgressIncludesWhatTheTaskAlreadyHad() {
    // 19 hours banked, one hour run: twenty hours, the band resets.
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertEqual(session.progress(at: t0), 0.95, accuracy: 1e-9)
    XCTAssertEqual(
      session.progress(at: t0.addingTimeInterval(hour)),
      0,
      accuracy: 1e-9,
      "a task at exactly twenty hours reads empty, not full"
    )
  }

  func testProgressOfAPausedSessionIsFrozen() {
    let session = SessionSnapshot(
      startedAt: t0,
      pausedAt: t0.addingTimeInterval(5 * hour),
      taskSecondsBefore: 5 * hour
    )

    XCTAssertEqual(session.progress(at: t0.addingTimeInterval(5 * hour)), 0.5)
    XCTAssertEqual(
      session.progress(at: t0.addingTimeInterval(19 * hour)),
      0.5,
      "a paused session fills no ring"
    )
  }

  func testCrossingTwentyHoursStartsTheNextMilestone() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    // Half an hour past the crossing: half an hour into the second band.
    let after = t0.addingTimeInterval(hour + 30 * 60)
    XCTAssertEqual(session.milestonesReached(at: after), 1)
    XCTAssertEqual(session.bandSeconds(at: after), 30 * 60, accuracy: 0.001)
    XCTAssertEqual(session.progress(at: after), 0.025, accuracy: 1e-9)
  }

  func testASessionLongEnoughToCrossTwoMilestones() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 10 * hour)
    let after = t0.addingTimeInterval(31 * hour) // 41h total

    XCTAssertEqual(session.milestonesReached(at: after), 2)
    XCTAssertEqual(session.bandSeconds(at: after), hour, accuracy: 0.001)
    XCTAssertEqual(session.progress(at: after), 0.05, accuracy: 1e-9)
  }

  // MARK: - Remaining, and the span the ring fills over

  func testRemainingIsWhatIsLeftOfTheBand() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)
    let now = t0.addingTimeInterval(48 * 60) // 16h48m

    XCTAssertEqual(session.remaining(at: now), 3 * hour + 12 * 60, accuracy: 0.001)
    XCTAssertEqual(
      session.milestoneDate(at: now),
      now.addingTimeInterval(3 * hour + 12 * 60)
    )
  }

  func testTheBandRangeDescribesExactlyTheProgressShown() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 7 * hour)
    let now = t0.addingTimeInterval(3 * hour)
    let range = session.bandRange(at: now)

    let fraction =
      now.timeIntervalSince(range.lowerBound)
      / range.upperBound.timeIntervalSince(range.lowerBound)
    XCTAssertEqual(fraction, session.progress(at: now), accuracy: 1e-9)
    XCTAssertEqual(
      range.upperBound,
      session.milestoneDate(at: now),
      "the ring must fill up at the same instant the milestone lands"
    )
  }

  func testTheBandRangeDoesNotMoveBetweenRenders() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 7 * hour)

    let early = session.bandRange(at: t0.addingTimeInterval(hour))
    let late = session.bandRange(at: t0.addingTimeInterval(hour + 30))

    XCTAssertEqual(early, late, "a re-render would make the ring jump")
  }

  func testTheBandRangeMovesOnWhenAMilestoneIsCrossed() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    let before = session.bandRange(at: t0.addingTimeInterval(30 * 60))
    let after = session.bandRange(at: t0.addingTimeInterval(90 * 60))

    XCTAssertEqual(
      after.lowerBound.timeIntervalSince(before.lowerBound),
      SessionSnapshot.milestoneSeconds,
      accuracy: 0.001,
      "the ring must start again on the next twenty hours"
    )
  }

  // MARK: - The projected crossing

  func testTheTargetIsTheFirstMilestoneAboveWhereTheTaskStood() {
    XCTAssertEqual(
      SessionSnapshot(startedAt: t0, taskSecondsBefore: 7 * hour).targetSeconds,
      20 * hour
    )
    XCTAssertEqual(
      SessionSnapshot(startedAt: t0, taskSecondsBefore: 31 * hour).targetSeconds,
      40 * hour
    )
  }

  func testATaskOnAnExactMilestoneAimsAtTheNextOne() {
    XCTAssertEqual(
      SessionSnapshot(startedAt: t0, taskSecondsBefore: 20 * hour).targetSeconds,
      40 * hour,
      "twenty hours exactly is an empty ring, so the next one is forty"
    )
  }

  func testProjectedRemainingMatchesRemainingUntilTheCrossing() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)
    let now = t0.addingTimeInterval(48 * 60)

    XCTAssertEqual(
      session.projectedRemaining(at: now),
      session.remaining(at: now),
      accuracy: 0.001,
      "nothing about the ordinary countdown may change"
    )
  }

  func testProjectedRemainingGoesNegativeOnceCrossedWhileRemainingResets() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)
    let past = t0.addingTimeInterval(90 * 60) // 20h30m on the task

    XCTAssertEqual(session.projectedRemaining(at: past), -30 * 60, accuracy: 0.001)
    XCTAssertEqual(
      session.remaining(at: past),
      19.5 * hour,
      accuracy: 0.001,
      "remaining springs back to the new band — which is why it cannot be the test for crossed"
    )
  }

  func testProjectedRemainingKeepsFallingThroughASecondMilestone() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)
    let farPast = t0.addingTimeInterval(21.5 * hour) // 40h30m on the task

    XCTAssertLessThan(
      session.projectedRemaining(at: farPast),
      0,
      "a second crossing is still crossed"
    )
  }

  // MARK: - The one push nobody makes: a minute before the crossing

  func testTheLastMinuteFiresOneMinuteBeforeTheCrossing() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)
    let now = t0.addingTimeInterval(48 * 60) // 3h12m to go

    XCTAssertEqual(
      session.staticLineFireDate(at: now),
      now.addingTimeInterval(3 * hour + 12 * 60 - 60)
    )
  }

  func testTheLastMinuteFireDateDoesNotDriftBetweenPushes() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 16 * hour)

    XCTAssertEqual(
      session.staticLineFireDate(at: t0.addingTimeInterval(hour)),
      session.staticLineFireDate(at: t0.addingTimeInterval(hour + 30)),
      "the crossing is a fixed instant; re-pushing must not move the booking"
    )
  }

  func testNothingToBookInsideTheLastMinute() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)
    let now = t0.addingTimeInterval(hour - 45) // 45s to go

    XCTAssertNil(session.staticLineFireDate(at: now), "the line is already static")
  }

  func testNothingToBookOnceCrossed() {
    let session = SessionSnapshot(startedAt: t0, taskSecondsBefore: 19 * hour)

    XCTAssertNil(session.staticLineFireDate(at: t0.addingTimeInterval(90 * 60)))
  }

  func testNothingToBookWhilePaused() {
    let pausedAt = t0.addingTimeInterval(30 * 60)
    let session = SessionSnapshot(startedAt: t0, pausedAt: pausedAt, taskSecondsBefore: 16 * hour)

    XCTAssertNil(
      session.staticLineFireDate(at: pausedAt.addingTimeInterval(600)),
      "a paused session is not approaching anything"
    )
  }

  func testAFreshSessionAfterAStopCountsDownFromTheNewRemaining() {
    // The stopped session's time is now part of the task, crossed hours
    // included: 19h before, ran 90m, so the new session starts at 20h30m.
    let next = SessionSnapshot(
      startedAt: t0,
      taskSecondsBefore: 20.5 * hour
    )

    XCTAssertEqual(next.targetSeconds, 40 * hour)
    XCTAssertEqual(next.projectedRemaining(at: t0), 19.5 * hour, accuracy: 0.001)
    XCTAssertEqual(next.staticLineFireDate(at: t0), t0.addingTimeInterval(19.5 * hour - 60))
  }

  // MARK: - Reading it out of the App Group

  func testReadsWhatTheAppWroteIntoSharedStorage() {
    let defaults = UserDefaults(suiteName: "group.sondr.tests")!
    defaults.removeObject(forKey: SessionSnapshot.key)
    XCTAssertNil(SessionSnapshot.current(in: defaults))

    defaults.set(
      json(["startedAt": 1_760_000_000_000, "pausedMs": 0, "taskName": "Learn piano"]),
      forKey: SessionSnapshot.key
    )

    XCTAssertEqual(SessionSnapshot.current(in: defaults)?.taskName, "Learn piano")
    defaults.removeObject(forKey: SessionSnapshot.key)
  }
}
