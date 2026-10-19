import Foundation

/// Where the session lives, as bytes.
///
/// `SessionSnapshot` decodes the session into something with arithmetic on
/// it. This reads and writes the dictionary underneath, because a button on
/// the Lock Screen has to change one field and put everything else back
/// exactly as it found it — including fields this build has never heard of.
enum SessionBox {
  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: SessionSnapshot.appGroup)
  }

  static func read(from defaults: UserDefaults?) -> [String: Any]? {
    guard
      let raw = defaults?.string(forKey: SessionSnapshot.key), !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return map
  }

  /// One key, one value, one call: the whole session is replaced or none of
  /// it is. There is no state in which half a session is written down.
  @discardableResult
  static func write(_ session: [String: Any], to defaults: UserDefaults?) -> Bool {
    guard
      let defaults,
      let data = try? JSONSerialization.data(
        withJSONObject: session, options: [.sortedKeys]
      ),
      let raw = String(data: data, encoding: .utf8)
    else { return false }
    defaults.set(raw, forKey: SessionSnapshot.key)
    return true
  }
}

/// Pausing and resuming a session without the app.
///
/// The Lock Screen's buttons run here, in whatever process the system picks
/// to run them, with no Flutter engine and possibly no app. So the
/// transform is the one `SessionClock.pause` / `.resume` does in Dart,
/// written out again in Swift — see
/// `lib/features/timer/session_clock.dart`, and the tests on both sides.
///
/// Every other field is carried across untouched. A field a newer build
/// writes, or one this build simply does not read, must survive a tap on a
/// button that knows nothing about it.
enum SessionMutation {
  /// Stamp the moment a running session stopped.
  ///
  /// Nil when there is nothing to do — already paused, or not a session.
  /// Tapping Pause twice must leave the second tap with nothing to write.
  static func pause(_ session: [String: Any], at now: Date) -> [String: Any]? {
    guard session["startedAt"] is NSNumber else { return nil }
    guard !(session["pausedAt"] is NSNumber) else { return nil }
    var next = session
    next["pausedAt"] = milliseconds(now)
    return next
  }

  /// Fold the pause into the running total and start counting again.
  ///
  /// Nil when the session is already running. A clock moved backwards
  /// cannot subtract time: a negative pause counts as none.
  static func resume(_ session: [String: Any], at now: Date) -> [String: Any]? {
    guard session["startedAt"] is NSNumber else { return nil }
    guard let pausedAt = session["pausedAt"] as? NSNumber else { return nil }
    let waited = max(0, milliseconds(now) - pausedAt.int64Value)
    let before = (session["pausedMs"] as? NSNumber)?.int64Value ?? 0
    var next = session
    next["pausedMs"] = before + waited
    next.removeValue(forKey: "pausedAt")
    return next
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}
