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

  // MARK: - The dial's band

  /// The same numbers Home's dial_geometry_test.dart asserts, in turns.
  private func snapshot(_ seconds: [Int], selected: String) -> WidgetSnapshot {
    WidgetSnapshot(
      tasks: seconds.indices.map {
        WidgetTask(id: "t\($0)", name: "T\($0)", today: seconds[$0])
      },
      segments: seconds,
      selectedTaskId: selected
    )
  }

  func testSlicesAreTheSharesLeftAfterTheSlits() {
    let starts = DialBand.starts(weights: [1, 1, 2], slit: 0.01)
    // Three slits take 0.03 of the turn; 0.97 is split 1/4, 1/4, 1/2.
    XCTAssertEqual(starts[0], 0, accuracy: 1e-9)
    XCTAssertEqual(starts[1], 0.97 * 0.25 + 0.01, accuracy: 1e-9)
    XCTAssertEqual(starts[2], 0.97 * 0.5 + 0.02, accuracy: 1e-9)
    XCTAssertEqual(DialBand.sweeps(weights: [1, 1, 2], slit: 0.01).reduce(0, +),
                   0.97, accuracy: 1e-9)
  }

  func testTheSelectedSliceOpensAtTwelve() {
    for count in 1 ... 5 {
      let weights = (1 ... count).map { Double($0) * 600 }
      let slit = count > 1 ? 0.01 : 0
      let starts = DialBand.starts(weights: weights, slit: slit)
      for selected in 0 ..< count {
        let turn = DialBand.rotation(starts: starts, selected: selected)
        // What the band is drawn from, for the selected slice.
        let opening = (starts[selected] - turn)
          .truncatingRemainder(dividingBy: 1)
        XCTAssertEqual(opening, 0, accuracy: 1e-9,
                       "\(count) tasks, slice \(selected)")
      }
    }
  }

  func testTurningKeepsEveryOtherSliceInOrder() {
    let weights: [Double] = [600, 1800, 3600]
    let starts = DialBand.starts(weights: weights, slit: 0.01)
    let turn = DialBand.rotation(starts: starts, selected: 2)
    let turned = starts.map { start -> Double in
      let x = (start - turn).truncatingRemainder(dividingBy: 1)
      return x < 0 ? x + 1 : x
    }
    // The selected one is at 12 and the two before it have wrapped round
    // to the end, in their own order — not reordered.
    XCTAssertEqual(turned[2], 0, accuracy: 1e-9)
    XCTAssertTrue(turned[0] < turned[1], "order kept: \(turned)")
    XCTAssertTrue(turned[2] < turned[0], "the selected one leads")
  }

  func testOnlyTasksWithTimeTodayGetASlice() {
    let snap = snapshot([3600, 0, 1200], selected: "t2")
    let entries = DialBand.entries(snap)
    XCTAssertEqual(entries.map(\.index), [0, 2])
    XCTAssertEqual(entries.map(\.seconds), [3600, 1200])
  }

  func testASelectedTaskWithNoTimeTodayDoesNotTurnTheBand() {
    let snap = snapshot([3600, 0, 1200], selected: "t1")
    let entries = DialBand.entries(snap)
    let selected = entries.firstIndex { snap.tasks[$0.index].id == "t1" }
    XCTAssertNil(selected)
    let starts = DialBand.starts(
      weights: entries.map { Double($0.seconds) }, slit: 0.01
    )
    XCTAssertEqual(DialBand.rotation(starts: starts, selected: selected), 0)
  }

  func testOneSliceIsTheWholeRing() {
    XCTAssertEqual(DialBand.starts(weights: [900], slit: 0), [0])
    XCTAssertEqual(DialBand.sweeps(weights: [900], slit: 0), [1])
  }
}
