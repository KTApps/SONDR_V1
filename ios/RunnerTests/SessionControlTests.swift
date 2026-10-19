import XCTest

/// What a button on the card actually does, end to end, minus the drawing.
///
/// `SessionControl.apply` is the whole of an intent's work: read the
/// session out of shared storage, transform it, write it back, then tell
/// the card. These cover everything but the last step, which needs a live
/// activity to talk to.
@available(iOS 17.0, *)
final class SessionControlTests: XCTestCase {
  private let suite = "group.sondr.control.tests"
  private var defaults: UserDefaults!
  private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suite)
    defaults.removeObject(forKey: SessionSnapshot.key)
  }

  override func tearDown() {
    defaults.removeObject(forKey: SessionSnapshot.key)
    super.tearDown()
  }

  private func put(_ session: [String: Any]) {
    XCTAssertTrue(SessionBox.write(session, to: defaults))
  }

  private func stored() -> [String: Any]? { SessionBox.read(from: defaults) }

  private func ms(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

  private func running() -> [String: Any] {
    [
      "startedAt": 1_760_000_000_000, "pausedMs": 0,
      "taskId": "task-7", "taskName": "Learn piano",
      "taskSecondsBefore": 57_600, "confirmedMs": 10_800_000,
    ]
  }

  func testPauseWritesTheMomentAndKeepsEverythingElse() async {
    put(running())

    await SessionControl.apply(
      .pause, now: t0.addingTimeInterval(3600), defaults: defaults
    )

    let after = stored()
    XCTAssertEqual(ms(after?["pausedAt"]), 1_760_003_600_000)
    XCTAssertEqual(after?["taskName"] as? String, "Learn piano")
    XCTAssertEqual(ms(after?["confirmedMs"]), 10_800_000)
    XCTAssertEqual(ms(after?["taskSecondsBefore"]), 57_600)
  }

  func testResumeFoldsThePauseIn() async {
    var session = running()
    session["pausedAt"] = 1_760_001_800_000  // paused at +30m
    put(session)

    await SessionControl.apply(
      .resume, now: t0.addingTimeInterval(50 * 60), defaults: defaults
    )

    let after = stored()
    XCTAssertEqual(ms(after?["pausedMs"]), 20 * 60 * 1000)
    XCTAssertNil(after?["pausedAt"])
  }

  func testPausingATwiceTappedButtonChangesNothing() async {
    put(running())
    await SessionControl.apply(
      .pause, now: t0.addingTimeInterval(3600), defaults: defaults
    )
    let once = stored()

    await SessionControl.apply(
      .pause, now: t0.addingTimeInterval(7200), defaults: defaults
    )

    XCTAssertEqual(
      ms(stored()?["pausedAt"]), ms(once?["pausedAt"]),
      "the second tap moved the moment the session stopped"
    )
  }

  func testResumingARunningSessionChangesNothing() async {
    put(running())

    await SessionControl.apply(
      .resume, now: t0.addingTimeInterval(3600), defaults: defaults
    )

    XCTAssertEqual(ms(stored()?["pausedMs"]), 0, "a pause that never happened")
    XCTAssertNil(stored()?["pausedAt"])
  }

  func testNoSessionMeansNothingIsWritten() async {
    await SessionControl.apply(.pause, now: t0, defaults: defaults)

    XCTAssertNil(stored(), "a card with no session behind it invented one")
  }

  func testAFullCycleLeavesTheElapsedTimeRight() async {
    put(running())

    await SessionControl.apply(
      .pause, now: t0.addingTimeInterval(3600), defaults: defaults
    )
    await SessionControl.apply(
      .resume, now: t0.addingTimeInterval(3 * 3600), defaults: defaults
    )

    let session = SessionSnapshot.from(stored()!)!
    XCTAssertFalse(session.isPaused)
    XCTAssertEqual(
      session.elapsed(at: t0.addingTimeInterval(3 * 3600)),
      3600,
      "two hours paused should not count as work"
    )
  }
}
