import XCTest

/// What a tap on the widget writes.
///
/// Every one of these runs against a real UserDefaults suite of its own,
/// because what is being tested is the handover: the widget writes where
/// the app reads, and the app reads what the widget wrote.
@available(iOS 17.0, *)
final class WidgetIntentsTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suite: String!

  override func setUp() {
    super.setUp()
    suite = "sondr.widget.tests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  private func writeSnapshot(selected: String = "a", tasks: [[String: Any]]? = nil) {
    let map: [String: Any] = [
      "v": 1,
      "tasks": tasks ?? [
        ["id": "a", "name": "Golf", "today": 60, "total": 7200,
         "progress": 0.1, "last": "2026-10-24"],
        ["id": "b", "name": "Run", "today": 0, "total": 0,
         "progress": 0, "last": ""],
      ],
      "segments": [60, 0],
      "habitsDone": 1,
      "habitsTotal": 2,
      "selected": selected,
    ]
    let data = try! JSONSerialization.data(withJSONObject: map)
    defaults.set(String(decoding: data, as: UTF8.self), forKey: WidgetSnapshot.key)
  }

  // MARK: - Selection

  func testSelectingWritesBothPlacesTheAppLooks() {
    writeSnapshot(selected: "a")
    WidgetSelection.set("b", defaults: defaults)

    // The snapshot, so the widget redraws now...
    XCTAssertEqual(WidgetSnapshot.read(from: defaults)?.selectedTaskId, "b")
    // ...and the key the app reads at launch.
    XCTAssertEqual(WidgetSelection.pending(defaults: defaults), "b")
  }

  func testTheRestOfTheSnapshotSurvivesASelection() {
    writeSnapshot(selected: "a")
    WidgetSelection.set("b", defaults: defaults)
    let after = WidgetSnapshot.read(from: defaults)
    XCTAssertEqual(after?.tasks.count, 2)
    XCTAssertEqual(after?.segments, [60, 0])
    XCTAssertEqual(after?.habitsTotal, 2)
  }

  func testTheAppClearsWhatItHasTaken() {
    WidgetSelection.set("b", defaults: defaults)
    WidgetSelection.clear(defaults: defaults)
    XCTAssertNil(WidgetSelection.pending(defaults: defaults))
  }

  func testSelectingWithNoSnapshotYetStillRecordsIt() {
    WidgetSelection.set("b", defaults: defaults)
    XCTAssertEqual(WidgetSelection.pending(defaults: defaults), "b")
  }

  // MARK: - Starting

  func testStartingWritesASessionTheAppCanRead() async {
    writeSnapshot(selected: "a")
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let started = await SessionStart.begin(
      taskId: "a", now: now, defaults: defaults, requestCard: false
    )
    XCTAssertTrue(started)

    let session = SessionBox.read(from: defaults).flatMap(SessionSnapshot.from)
    XCTAssertEqual(session?.startedAt, now)
    XCTAssertEqual(session?.taskId, "a")
    XCTAssertEqual(session?.taskName, "Golf")
    // What the task had before, which is what fills the card's ring.
    XCTAssertEqual(session?.taskSecondsBefore, 7200)
    XCTAssertFalse(session?.isPaused ?? true)
  }

  func testStartingAlsoSelectsThatTask() async {
    writeSnapshot(selected: "a")
    _ = await SessionStart.begin(
      taskId: "b", defaults: defaults, requestCard: false
    )
    XCTAssertEqual(WidgetSnapshot.read(from: defaults)?.selectedTaskId, "b")
    XCTAssertEqual(WidgetSelection.pending(defaults: defaults), "b")
  }

  func testStartingDoesNothingWhileOneIsRunning() async {
    writeSnapshot(selected: "a")
    let first = Date(timeIntervalSince1970: 1_700_000_000)
    _ = await SessionStart.begin(
      taskId: "a", now: first, defaults: defaults, requestCard: false
    )
    let second = await SessionStart.begin(
      taskId: "b",
      now: first.addingTimeInterval(60),
      defaults: defaults,
      requestCard: false
    )
    XCTAssertFalse(second)
    let session = SessionBox.read(from: defaults).flatMap(SessionSnapshot.from)
    XCTAssertEqual(session?.startedAt, first, "the running session was replaced")
    XCTAssertEqual(session?.taskId, "a")
  }

  func testStartingWithNothingToStartDoesNothing() async {
    let started = await SessionStart.begin(
      taskId: "a", defaults: defaults, requestCard: false
    )
    XCTAssertFalse(started)
    XCTAssertNil(SessionBox.read(from: defaults))
  }

  func testTheSessionDocumentIsTheShapeDartWrites() {
    let doc = SessionStart.document(
      taskId: "a",
      taskName: "Golf",
      taskSecondsBefore: 7200,
      startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    XCTAssertEqual(
      Set(doc.keys),
      ["startedAt", "pausedMs", "taskId", "taskName", "taskSecondsBefore",
       "confirmedMs"]
    )
    // Milliseconds for the times, seconds for the task's total.
    XCTAssertEqual(doc["startedAt"] as? Int, 1_700_000_000_000)
    XCTAssertEqual(doc["taskSecondsBefore"] as? Int, 7200)
    XCTAssertNotNil(SessionSnapshot.from(doc))
  }

  // MARK: - Pausing, through the session the widget shares

  func testAPausedSessionReadsAsPaused() async {
    writeSnapshot(selected: "a")
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    _ = await SessionStart.begin(
      taskId: "a", now: now, defaults: defaults, requestCard: false
    )
    await SessionControl.apply(
      .pause, now: now.addingTimeInterval(60), defaults: defaults
    )
    let session = SessionBox.read(from: defaults).flatMap(SessionSnapshot.from)
    XCTAssertTrue(session?.isPaused ?? false)
    XCTAssertEqual(session?.elapsed(at: now.addingTimeInterval(600)), 60)
  }
}
