import XCTest

/// Pausing and resuming from the Lock Screen, with no app running.
///
/// The transform has to be the one `SessionClock` does in Dart and it has
/// to be careful with what it is handed: the session it reads was written
/// by the app, may contain fields this build does not read, and will be
/// read back by the app afterwards. Losing one of them loses the task, the
/// "Still going?" confirmation, or the ring.
final class SessionMutationTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
  private let hour: TimeInterval = 3600

  private func running(_ extra: [String: Any] = [:]) -> [String: Any] {
    var s: [String: Any] = ["startedAt": 1_760_000_000_000, "pausedMs": 0]
    extra.forEach { s[$0] = $1 }
    return s
  }

  private func ms(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

  // MARK: - Pause

  func testPauseStampsTheMoment() {
    let paused = SessionMutation.pause(running(), at: t0.addingTimeInterval(hour))

    XCTAssertEqual(ms(paused?["pausedAt"]), 1_760_003_600_000)
    XCTAssertEqual(ms(paused?["pausedMs"]), 0, "nothing accrues until the resume")
  }

  func testPausingAPausedSessionDoesNothing() {
    let already = running(["pausedAt": 1_760_001_800_000])

    XCTAssertNil(
      SessionMutation.pause(already, at: t0.addingTimeInterval(hour)),
      "a second tap would move the moment the session stopped"
    )
  }

  func testPauseRefusesAnythingThatIsNotASession() {
    XCTAssertNil(SessionMutation.pause([:], at: t0))
    XCTAssertNil(SessionMutation.pause(["pausedMs": 0], at: t0))
    XCTAssertNil(SessionMutation.pause(["startedAt": "soon"], at: t0))
  }

  // MARK: - Resume

  func testResumeFoldsThePauseIntoTheTotal() {
    let paused = running(["pausedAt": 1_760_001_800_000])  // paused at +30m

    let back = SessionMutation.resume(paused, at: t0.addingTimeInterval(50 * 60))

    XCTAssertEqual(ms(back?["pausedMs"]), 20 * 60 * 1000, "twenty minutes paused")
    XCTAssertNil(back?["pausedAt"], "a running session has no pausedAt")
  }

  func testResumeAddsToWhatWasAlreadyPaused() {
    let paused = running(["pausedMs": 5 * 60 * 1000, "pausedAt": 1_760_001_800_000])

    let back = SessionMutation.resume(paused, at: t0.addingTimeInterval(50 * 60))

    XCTAssertEqual(ms(back?["pausedMs"]), 25 * 60 * 1000)
  }

  func testResumingARunningSessionDoesNothing() {
    XCTAssertNil(SessionMutation.resume(running(), at: t0.addingTimeInterval(hour)))
  }

  func testAClockMovedBackwardsCannotSubtractTime() {
    let paused = running(["pausedMs": 60_000, "pausedAt": 1_760_003_600_000])

    let back = SessionMutation.resume(paused, at: t0)  // "now" is an hour earlier

    XCTAssertEqual(ms(back?["pausedMs"]), 60_000, "a negative pause counts as none")
  }

  // MARK: - Everything else survives

  func testEveryKnownFieldIsCarriedAcross() {
    let full = running([
      "taskId": "task-7",
      "taskName": "Learn piano",
      "taskSecondsBefore": 57_600,
      "confirmedMs": 10_800_000,
    ])

    let paused = SessionMutation.pause(full, at: t0.addingTimeInterval(hour))!
    let back = SessionMutation.resume(paused, at: t0.addingTimeInterval(2 * hour))!

    for session in [paused, back] {
      XCTAssertEqual(session["taskId"] as? String, "task-7")
      XCTAssertEqual(session["taskName"] as? String, "Learn piano")
      XCTAssertEqual(ms(session["taskSecondsBefore"]), 57_600)
      XCTAssertEqual(ms(session["confirmedMs"]), 10_800_000, "it would ask again")
      XCTAssertEqual(ms(session["startedAt"]), 1_760_000_000_000)
    }
  }

  func testAFieldThisBuildHasNeverHeardOfSurvives() {
    let future = running(["somethingNewer": "keep me", "aNumber": 42])

    let paused = SessionMutation.pause(future, at: t0.addingTimeInterval(hour))!
    let back = SessionMutation.resume(paused, at: t0.addingTimeInterval(2 * hour))!

    XCTAssertEqual(back["somethingNewer"] as? String, "keep me")
    XCTAssertEqual(ms(back["aNumber"]), 42)
  }

  // MARK: - Round trips

  func testPausedTimeAccumulatesAcrossSeveralCycles() {
    // Three ten-minute pauses over three hours of wall time.
    var session = running(["taskName": "Learn piano"])
    var at = t0
    for cycle in 0..<3 {
      at = t0.addingTimeInterval(Double(cycle) * hour + 30 * 60)
      session = SessionMutation.pause(session, at: at)!
      at = at.addingTimeInterval(10 * 60)
      session = SessionMutation.resume(session, at: at)!
    }

    XCTAssertEqual(ms(session["pausedMs"]), 30 * 60 * 1000)
    XCTAssertNil(session["pausedAt"])
    XCTAssertEqual(session["taskName"] as? String, "Learn piano")
  }

  func testElapsedIsRightAtEveryStepOfACycle() {
    var session = running()
    let snapshot = { SessionSnapshot.from(session)! }

    // An hour in, running.
    XCTAssertEqual(snapshot().elapsed(at: t0.addingTimeInterval(hour)), hour)

    // Paused at the hour: frozen there however long it sits.
    session = SessionMutation.pause(session, at: t0.addingTimeInterval(hour))!
    XCTAssertTrue(snapshot().isPaused)
    XCTAssertEqual(snapshot().elapsed(at: t0.addingTimeInterval(5 * hour)), hour)

    // Resumed after four hours paused: still an hour of work done.
    session = SessionMutation.resume(session, at: t0.addingTimeInterval(5 * hour))!
    XCTAssertFalse(snapshot().isPaused)
    XCTAssertEqual(snapshot().elapsed(at: t0.addingTimeInterval(5 * hour)), hour)

    // Another half hour of running makes ninety minutes.
    XCTAssertEqual(
      snapshot().elapsed(at: t0.addingTimeInterval(5.5 * hour)),
      hour + 30 * 60
    )
  }

  // MARK: - The box it is kept in

  func testWhatIsWrittenComesBack() {
    let defaults = UserDefaults(suiteName: "group.sondr.mutation.tests")!
    defaults.removeObject(forKey: SessionSnapshot.key)
    XCTAssertNil(SessionBox.read(from: defaults))

    let session = running(["taskName": "Learn piano", "somethingNewer": "keep me"])
    XCTAssertTrue(SessionBox.write(session, to: defaults))

    let back = SessionBox.read(from: defaults)
    XCTAssertEqual(ms(back?["startedAt"]), 1_760_000_000_000)
    XCTAssertEqual(back?["taskName"] as? String, "Learn piano")
    XCTAssertEqual(back?["somethingNewer"] as? String, "keep me")
    defaults.removeObject(forKey: SessionSnapshot.key)
  }

  func testWritingNowhereFailsRatherThanPretending() {
    XCTAssertFalse(SessionBox.write(running(), to: nil))
  }
}
