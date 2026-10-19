import XCTest

/// The same sessions, checked on this side of the App Group.
///
/// `test/fixtures/sessions.json` is read by this file and by
/// `test/session_contract_test.dart`. Two languages, two processes, one set
/// of bytes: if they ever disagree about how long a session has run, the
/// Lock Screen is lying about how long someone has worked, and nothing in
/// either suite on its own would notice.
final class SharedFixtureTests: XCTestCase {
  private struct Case {
    let name: String
    let session: [String: Any]
    let now: Date
    let elapsed: TimeInterval
  }

  private func load() throws -> [Case] {
    let bundle = Bundle(for: type(of: self))
    guard let url = bundle.url(forResource: "sessions", withExtension: "json")
    else {
      XCTFail("sessions.json is not in the test bundle")
      return []
    }
    let root =
      try JSONSerialization.jsonObject(with: Data(contentsOf: url))
      as! [String: Any]
    return (root["cases"] as! [[String: Any]]).map {
      Case(
        name: $0["name"] as! String,
        session: $0["session"] as! [String: Any],
        now: Date(
          timeIntervalSince1970: ($0["nowMs"] as! NSNumber).doubleValue / 1000
        ),
        elapsed: ($0["elapsedMs"] as! NSNumber).doubleValue / 1000
      )
    }
  }

  func testThereAreCasesToCheck() throws {
    XCTAssertFalse(try load().isEmpty)
  }

  func testElapsedMatchesDartForEverySession() throws {
    for c in try load() {
      guard let session = SessionSnapshot.from(c.session) else {
        XCTFail("\(c.name): Swift would not read a session Dart accepts")
        continue
      }
      XCTAssertEqual(
        session.elapsed(at: c.now),
        c.elapsed,
        accuracy: 0.001,
        "\(c.name): Dart and Swift disagree about this session"
      )
    }
  }
}
