import Darwin
import Foundation

/// Where the session lives, as bytes.
///
/// `SessionSnapshot` decodes the session into something with arithmetic on
/// it. This reads and writes the dictionary underneath, because a button on
/// the Lock Screen has to change one field and put everything else back
/// exactly as it found it — including fields this build has never heard of.
/// Saying, to anyone listening, that the stored session just changed.
///
/// A Darwin notification is the one signal that crosses processes on iOS
/// without either side being awake for the other: the extension posts,
/// and a running app hears it at once. The app observes it in
/// SessionActivityChannel and re-reads the session — nothing polls, and
/// nothing is carried in the notification itself, because the App Group
/// already holds the truth.
enum SessionBroadcast {
  static let name = "com.tanakabere.sondr.sessionChanged"

  static func post() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(name as CFString),
      nil,
      nil,
      true
    )
  }
}

/// When this process started — if this process is the app.
///
/// A tap on the widget or the card runs a LiveActivityIntent, and the
/// system launches the app to perform it. By the time `perform()` reads
/// the clock the tap is a launch behind. The kernel knows when the
/// process started; if the intent performs within a breath of that, the
/// launch WAS the tap, and the start time is the nearest thing to the tap
/// time that exists on this platform. Recorded by AppDelegate; never set
/// in the extension, so an intent performed there uses its own clock,
/// which is the tap time already.
enum LaunchAnchor {
  static private(set) var processLaunchedAt: Date?

  /// How soon after launch a performed intent is taken to have caused it.
  static let threshold: TimeInterval = 2.5

  static func record() {
    processLaunchedAt = ProcessStart.time ?? Date()
  }
}

/// The kernel's record of when this process began.
enum ProcessStart {
  static var time: Date? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
    let tv = info.kp_proc.p_starttime
    return Date(
      timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
    )
  }
}

/// The instant a tap happened, as near as this process can tell.
enum TapTime {
  struct Resolution: Equatable {
    let stamp: Date
    /// Whether the stamp is earlier than the clock said.
    let backDated: Bool
    /// How long this process had been alive, if that is known here.
    let launchAge: TimeInterval?
  }

  /// `now` is the clock at perform; `launchedAt` the process start, if
  /// this is the app; `notBefore` the session's last written instant,
  /// which no stamp may precede — a pause cannot come before the start it
  /// pauses, nor a resume before the pause it ends.
  static func resolve(
    now: Date,
    launchedAt: Date?,
    notBefore: Date?,
    threshold: TimeInterval = LaunchAnchor.threshold
  ) -> Resolution {
    var stamp = now
    var age: TimeInterval?
    if let launchedAt {
      let a = now.timeIntervalSince(launchedAt)
      age = a
      if a >= 0 && a <= threshold { stamp = launchedAt }
    }
    if let notBefore, stamp < notBefore { stamp = notBefore }
    if stamp > now { stamp = now }
    return Resolution(stamp: stamp, backDated: stamp < now, launchAge: age)
  }
}

/// What each intent did with its clock — for the debug panel only.
///
/// Written only when the app has left `sondr.debug.enabled` in the App
/// Group, which it does under DEBUG_TOOLS and never otherwise, so a
/// release build neither writes nor reads this.
enum IntentTrace {
  static let key = "sondr.debug.intents"
  static let enabledKey = "sondr.debug.enabled"

  static func record(
    _ kind: String,
    performedAt: Date,
    _ tap: TapTime.Resolution,
    defaults: UserDefaults? = SessionBox.sharedDefaults
  ) {
    guard let defaults, defaults.bool(forKey: enabledKey) else { return }
    var entries: [[String: Any]] = []
    if let raw = defaults.string(forKey: key), let data = raw.data(using: .utf8),
      let old = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
      entries = old
    }
    entries.append([
      "kind": kind,
      "performedAt": Int64(performedAt.timeIntervalSince1970 * 1000),
      "launchAge": tap.launchAge.map { Int($0 * 1000) } ?? -1,
      "backDated": tap.backDated,
      "finalStamp": Int64(tap.stamp.timeIntervalSince1970 * 1000),
      "process": Bundle.main.bundleIdentifier ?? "?",
    ])
    guard let out = try? JSONSerialization.data(withJSONObject: Array(entries.suffix(3)))
    else { return }
    defaults.set(String(decoding: out, as: UTF8.self), forKey: key)
  }
}

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
