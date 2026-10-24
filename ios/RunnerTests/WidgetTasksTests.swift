import XCTest

/// What the Home Screen widget reads, and which tasks it shows.
///
/// The document is written by Dart (lib/features/widget/widget_snapshot.dart)
/// and read here; the field names and units are the whole agreement, so
/// these are the tests that keep the two sides honest.
final class WidgetTasksTests: XCTestCase {
  private func json(
    tasks: [[String: Any]] = [],
    segments: [Int] = [],
    habitsDone: Int = 0,
    habitsTotal: Int = 0,
    selected: String = ""
  ) -> String {
    let map: [String: Any] = [
      "v": 1,
      "tasks": tasks,
      "segments": segments,
      "habitsDone": habitsDone,
      "habitsTotal": habitsTotal,
      "selected": selected,
    ]
    let data = try! JSONSerialization.data(withJSONObject: map)
    return String(decoding: data, as: UTF8.self)
  }

  private func task(
    _ id: String,
    today: Int = 0,
    total: Int = 0,
    progress: Double = 0,
    last: String = ""
  ) -> [String: Any] {
    [
      "id": id,
      "name": id.capitalized,
      "today": today,
      "total": total,
      "progress": progress,
      "last": last,
    ]
  }

  // MARK: - The document

  func testReadsWhatDartWrote() {
    let snapshot = WidgetSnapshot.from(
      json(
        tasks: [task("golf", today: 3600, total: 72000, progress: 0.5, last: "2026-10-24")],
        segments: [3600],
        habitsDone: 1,
        habitsTotal: 3,
        selected: "golf"
      )
    )
    XCTAssertEqual(snapshot?.tasks.count, 1)
    let golf = snapshot!.tasks[0]
    XCTAssertEqual(golf.id, "golf")
    XCTAssertEqual(golf.name, "Golf")
    XCTAssertEqual(golf.today, 3600)
    XCTAssertEqual(golf.total, 72000)
    XCTAssertEqual(golf.progress, 0.5)
    XCTAssertEqual(golf.lastTracked, "2026-10-24")
    XCTAssertEqual(snapshot?.segments, [3600])
    XCTAssertEqual(snapshot?.habitsDone, 1)
    XCTAssertEqual(snapshot?.habitsTotal, 3)
    XCTAssertEqual(snapshot?.selectedTaskId, "golf")
  }

  func testNothingToReadIsNothing() {
    XCTAssertNil(WidgetSnapshot.from(nil))
    XCTAssertNil(WidgetSnapshot.from(""))
    XCTAssertNil(WidgetSnapshot.from("not json"))
  }

  func testAMalformedTaskIsDroppedRatherThanGuessed() {
    let snapshot = WidgetSnapshot.from(
      json(tasks: [task("golf"), ["name": "no id"]])
    )
    XCTAssertEqual(snapshot?.tasks.map(\.id), ["golf"])
  }

  func testSelectedFallsBackToTheFirst() {
    let snapshot = WidgetSnapshot.from(
      json(tasks: [task("golf"), task("run")], selected: "gone")
    )
    XCTAssertEqual(snapshot?.selected?.id, "golf")
  }

  func testACompletedMilestoneIsOnlyAtTheTop() {
    XCTAssertFalse(WidgetTask(id: "a", name: "A", progress: 0.99).isMilestoneComplete)
    XCTAssertTrue(WidgetTask(id: "a", name: "A", progress: 1).isMilestoneComplete)
    // Progress resets at each milestone, so a task just past one reads
    // empty — the same rule the app's rings follow.
    XCTAssertFalse(WidgetTask(id: "a", name: "A", progress: 0).isMilestoneComplete)
  }

  // MARK: - Which tasks a widget shows

  func testAutomaticIsTheFiveMostRecentlyTracked() {
    let tasks = [
      WidgetTask(id: "a", name: "A", lastTracked: "2026-10-01"),
      WidgetTask(id: "b", name: "B", lastTracked: "2026-10-24"),
      WidgetTask(id: "c", name: "C", lastTracked: "2026-10-20"),
      WidgetTask(id: "d", name: "D", lastTracked: "2026-10-23"),
      WidgetTask(id: "e", name: "E", lastTracked: "2026-10-22"),
      WidgetTask(id: "f", name: "F", lastTracked: "2026-10-21"),
    ]
    XCTAssertEqual(
      WidgetList.automatic(tasks).map(\.id),
      ["b", "d", "e", "f", "c"]
    )
    XCTAssertEqual(WidgetList.automatic(tasks).count, WidgetList.maximum)
  }

  func testNeverTrackedKeepsTheAppsOwnOrder() {
    let tasks = [
      WidgetTask(id: "a", name: "A"),
      WidgetTask(id: "b", name: "B"),
    ]
    XCTAssertEqual(WidgetList.automatic(tasks).map(\.id), ["a", "b"])
  }

  func testAChosenListKeepsItsOrderAndItsCap() {
    let snapshot = WidgetSnapshot(tasks: [
      WidgetTask(id: "a", name: "A"),
      WidgetTask(id: "b", name: "B"),
      WidgetTask(id: "c", name: "C"),
      WidgetTask(id: "d", name: "D"),
      WidgetTask(id: "e", name: "E"),
      WidgetTask(id: "f", name: "F"),
    ])
    XCTAssertEqual(
      WidgetList.chosen(["c", "a", "b"], from: snapshot).map(\.id),
      ["c", "a", "b"]
    )
    XCTAssertEqual(
      WidgetList.chosen(["a", "b", "c", "d", "e", "f"], from: snapshot).count,
      WidgetList.maximum
    )
  }

  func testAChosenTaskThatIsGoneDropsOut() {
    let snapshot = WidgetSnapshot(tasks: [WidgetTask(id: "a", name: "A")])
    XCTAssertEqual(
      WidgetList.chosen(["a", "deleted"], from: snapshot).map(\.id),
      ["a"]
    )
  }

  // MARK: - Cycling

  func testCyclingWrapsAroundTheList() {
    let list = [
      WidgetTask(id: "a", name: "A"),
      WidgetTask(id: "b", name: "B"),
      WidgetTask(id: "c", name: "C"),
    ]
    XCTAssertEqual(WidgetList.next(after: "a", in: list)?.id, "b")
    XCTAssertEqual(WidgetList.next(after: "c", in: list)?.id, "a")
    // An id that is not in the list starts at the beginning.
    XCTAssertEqual(WidgetList.next(after: "gone", in: list)?.id, "a")
  }

  func testAListOfOneHasNowhereToGo() {
    let list = [WidgetTask(id: "a", name: "A")]
    XCTAssertNil(WidgetList.next(after: "a", in: list))
    XCTAssertNil(WidgetList.next(after: "a", in: []))
  }
}
