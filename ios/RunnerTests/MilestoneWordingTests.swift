import XCTest

/// The paused card writes the milestone line itself; the running card hands
/// it to the system. They have to come out in the same words, or pausing
/// rewords the sentence as well as stopping the clock.
///
/// The strings below are what `Text(date, style: .relative)` renders for
/// the same remaining times, read off the Lock Screen at @3x.
final class MilestoneWordingTests: XCTestCase {
  private let hour: TimeInterval = 3600

  func testHoursAndMinutes() {
    XCTAssertEqual(MilestoneWording.remaining(3 * hour + 8 * 60), "3 hrs, 8 min")
  }

  func testAWholeHourDropsTheMinutes() {
    XCTAssertEqual(
      MilestoneWording.remaining(hour),
      "1 hr",
      "a zero minute would read 1 hr, 0 min"
    )
  }

  func testMinutesAlone() {
    XCTAssertEqual(MilestoneWording.remaining(45 * 60), "45 min")
  }

  func testOneMinute() {
    XCTAssertEqual(MilestoneWording.remaining(60), "1 min")
  }

  func testLessThanAMinuteIsStillAMinute() {
    XCTAssertEqual(
      MilestoneWording.remaining(12),
      "1 min",
      "dropping the zero would leave the sentence with no subject"
    )
    XCTAssertEqual(MilestoneWording.remaining(0), "1 min")
  }

  func testSecondsNeverAppear() {
    // 3h 8m 29s rounds down to the minute, not "3 hrs, 8 min, 29 sec".
    XCTAssertEqual(
      MilestoneWording.remaining(3 * hour + 8 * 60 + 29),
      "3 hrs, 8 min"
    )
  }

  func testATwentyHourBandAtItsFullest() {
    XCTAssertEqual(MilestoneWording.remaining(20 * hour), "20 hrs")
  }
}
