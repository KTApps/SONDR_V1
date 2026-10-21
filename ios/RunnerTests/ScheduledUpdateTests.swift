import XCTest

/// The booking for the one push nobody makes. It has to fire when asked,
/// not fire when cancelled, and keep only the latest booking.
final class ScheduledUpdateTests: XCTestCase {
  func testFiresAtTheBookedInstant() async {
    let update = ScheduledUpdate()
    let fired = expectation(description: "fired")

    update.schedule(at: Date().addingTimeInterval(0.2)) { fired.fulfill() }

    XCTAssertTrue(update.isScheduled)
    await fulfillment(of: [fired], timeout: 2)
  }

  func testCancelledBookingNeverFires() async {
    let update = ScheduledUpdate()
    let fired = expectation(description: "fired")
    fired.isInverted = true

    update.schedule(at: Date().addingTimeInterval(0.2)) { fired.fulfill() }
    update.cancel()

    XCTAssertFalse(update.isScheduled)
    await fulfillment(of: [fired], timeout: 0.6)
  }

  func testRebookingReplacesTheEarlierBooking() async {
    let update = ScheduledUpdate()
    let first = expectation(description: "first")
    first.isInverted = true
    let second = expectation(description: "second")

    update.schedule(at: Date().addingTimeInterval(0.2)) { first.fulfill() }
    update.schedule(at: Date().addingTimeInterval(0.3)) { second.fulfill() }

    await fulfillment(of: [first, second], timeout: 2)
  }

  func testABookingAlreadyDueRunsAtOnce() async {
    let update = ScheduledUpdate()
    let fired = expectation(description: "fired")

    update.schedule(at: Date().addingTimeInterval(-5)) { fired.fulfill() }

    await fulfillment(of: [fired], timeout: 1)
  }

  func testNothingBookedIsNothingScheduled() {
    XCTAssertFalse(ScheduledUpdate().isScheduled)
  }
}
