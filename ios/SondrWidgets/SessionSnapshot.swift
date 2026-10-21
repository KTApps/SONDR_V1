import Foundation

/// The running session, as Swift sees it.
///
/// Dart writes this as JSON into the App Group — see
/// `lib/features/timer/session_store.dart` for the shape and
/// `test/session_contract_test.dart` for the tests this file mirrors. The two
/// processes never talk: the field names, the units and the arithmetic below
/// are the whole agreement, so a change here is a change there.
///
/// Elapsed is derived, never accumulated, exactly as in `SessionClock`.
struct SessionSnapshot: Equatable {
  /// Where the session is kept, and under what name. The key has no
  /// `flutter.` prefix: the Dart side writes it through the async
  /// shared_preferences API, which stores keys verbatim.
  static let appGroup = "group.com.tanakabere.sondr"
  static let key = "sondr.session"

  /// A milestone every twenty hours. `Task.milestoneStepHours` in Dart.
  static let milestoneSeconds: TimeInterval = 20 * 60 * 60

  init(
    startedAt: Date,
    pausedTotal: TimeInterval = 0,
    pausedAt: Date? = nil,
    taskId: String? = nil,
    taskName: String? = nil,
    taskSecondsBefore: TimeInterval = 0,
    confirmedAt: TimeInterval = 0
  ) {
    self.startedAt = startedAt
    self.pausedTotal = pausedTotal
    self.pausedAt = pausedAt
    self.taskId = taskId
    self.taskName = taskName
    self.taskSecondsBefore = taskSecondsBefore
    self.confirmedAt = confirmedAt
  }

  /// When Start was first pressed.
  let startedAt: Date

  /// Everything spent paused before the current pause.
  let pausedTotal: TimeInterval

  /// When the current pause began; nil while running.
  let pausedAt: Date?

  let taskId: String?

  /// The task's name, and what it had logged before this session. Written by
  /// the app for this extension's benefit: with them the ring can be filled
  /// and the card named without a network call.
  let taskName: String?
  let taskSecondsBefore: TimeInterval

  /// The elapsed reading at which someone last confirmed the session is
  /// real. Unused here — carried so a round trip through this struct cannot
  /// lose it.
  let confirmedAt: TimeInterval

  var isPaused: Bool { pausedAt != nil }

  /// How long the session has run, at `now`.
  ///
  /// While paused the answer stops moving. A clock moved backwards — a
  /// timezone change, an NTP correction — must never produce a negative
  /// session.
  func elapsed(at now: Date) -> TimeInterval {
    let end = pausedAt ?? now
    return max(0, end.timeIntervalSince(startedAt) - pausedTotal)
  }

  /// The instant at which the elapsed reading was zero.
  ///
  /// `Text(timerInterval:)` counts from a date, not a duration, so paused
  /// time has to be folded into the start: `now - countingFrom` is the
  /// elapsed time, and the system does that subtraction on the device with
  /// nothing pushed to it.
  var countingFrom: Date { startedAt.addingTimeInterval(pausedTotal) }

  /// The task's total seconds at `now`, this session included.
  func taskSeconds(at now: Date) -> TimeInterval {
    taskSecondsBefore + elapsed(at: now)
  }

  /// How many twenty-hour milestones the task has passed at `now`.
  func milestonesReached(at now: Date) -> Double {
    (taskSeconds(at: now) / Self.milestoneSeconds).rounded(.down)
  }

  /// Seconds into the milestone currently being filled, at `now`.
  ///
  /// Resets to zero on each crossing, the same as `Task.milestoneProgress`:
  /// a task at exactly twenty hours reads empty, not full.
  func bandSeconds(at now: Date) -> TimeInterval {
    taskSeconds(at: now) - milestonesReached(at: now) * Self.milestoneSeconds
  }

  /// 0..1 through the current milestone, at `now`.
  func progress(at now: Date) -> Double {
    bandSeconds(at: now) / Self.milestoneSeconds
  }

  /// How much longer this task must run to reach its next milestone.
  func remaining(at now: Date) -> TimeInterval {
    Self.milestoneSeconds - bandSeconds(at: now)
  }

  /// When the next milestone lands if the session keeps running.
  func milestoneDate(at now: Date) -> Date {
    now.addingTimeInterval(remaining(at: now))
  }

  /// The milestone this session set out to reach: the first one strictly
  /// above where the task already stood when Start was pressed.
  ///
  /// Anchored to the session rather than to `now`, and that is the whole
  /// point. `bandSeconds` resets at every crossing, so `remaining` springs
  /// back to a full twenty hours the instant a milestone passes — right for
  /// a ring that begins filling again, useless for a card that has to say
  /// the milestone was reached. This target does not move while the session
  /// runs, so the time to it keeps falling and goes negative once crossed.
  ///
  /// A task sitting on an exact multiple counts as having reached that one
  /// already and aims at the next, which is the same reading `bandSeconds`
  /// gives: twenty hours exactly is an empty ring, not a full one.
  var targetSeconds: TimeInterval {
    (taskSecondsBefore / Self.milestoneSeconds).rounded(.down) * Self.milestoneSeconds
      + Self.milestoneSeconds
  }

  /// How long until this session reaches `targetSeconds`; negative once it
  /// has.
  ///
  /// Identical to `remaining(at:)` right up to the crossing. The two part
  /// company only afterwards, which is the one moment that matters here.
  func projectedRemaining(at now: Date) -> TimeInterval {
    targetSeconds - taskSeconds(at: now)
  }

  /// The instant this session crosses, projected from `now`.
  func projectedMilestoneDate(at now: Date) -> Date {
    now.addingTimeInterval(projectedRemaining(at: now))
  }

  /// Inside this much of the crossing, the card stops counting.
  ///
  /// The running card's countdown is `Text(_, style: .relative)`, handed
  /// to the system as a date so it keeps moving without the app awake.
  /// Nothing stops it at zero: left alone past the crossing it turns round
  /// and counts back up. So the last minute is drawn as a fixed string
  /// instead — nothing in it can move, so nothing can move the wrong way.
  static let lastMinuteSeconds: TimeInterval = 60

  /// When a running card should be redrawn so that the last minute lands
  /// without anyone touching the phone: one minute before the crossing.
  /// Nil while paused, nil once inside the last minute (already static),
  /// nil once crossed (nothing left to wait for).
  func staticLineFireDate(at now: Date) -> Date? {
    guard !isPaused else { return nil }
    let remaining = projectedRemaining(at: now)
    guard remaining > Self.lastMinuteSeconds else { return nil }
    return now.addingTimeInterval(remaining - Self.lastMinuteSeconds)
  }

  /// The current milestone as a span of time: empty at the lower bound,
  /// full at the upper.
  ///
  /// This is what lets the ring fill on the device with nothing pushed to
  /// it. Anchored to the session rather than to `now`, so two renders a
  /// second apart describe the same span and the ring cannot jump: the lower
  /// bound is `now - bandSeconds` rearranged to drop `now` entirely.
  ///
  /// Only meaningful while the session runs — the rearrangement assumes time
  /// is still accruing. A paused ring is a fixed fraction, not a span, and
  /// uses `progress(at:)`.
  func bandRange(at now: Date) -> ClosedRange<Date> {
    let start = countingFrom.addingTimeInterval(
      milestonesReached(at: now) * Self.milestoneSeconds - taskSecondsBefore
    )
    return start...start.addingTimeInterval(Self.milestoneSeconds)
  }

  /// Read the session the app last wrote, or nil if there is none.
  static func current(
    in defaults: UserDefaults? = UserDefaults(suiteName: appGroup)
  ) -> SessionSnapshot? {
    decode(defaults?.string(forKey: key))
  }

  /// Nil for anything that is not a session the app wrote.
  static func decode(_ raw: String?) -> SessionSnapshot? {
    guard
      let raw, !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return from(map)
  }

  /// The same fields, straight from a dictionary.
  ///
  /// The app hands the session over a method channel as a map rather than a
  /// string, and it must read identically either way — one reader, so the
  /// two routes cannot drift.
  static func from(_ map: [String: Any]) -> SessionSnapshot? {
    guard let startedAt = date(map["startedAt"]) else { return nil }
    return SessionSnapshot(
      startedAt: startedAt,
      pausedTotal: millis(map["pausedMs"]),
      pausedAt: date(map["pausedAt"]),
      taskId: map["taskId"] as? String,
      taskName: map["taskName"] as? String,
      taskSecondsBefore: seconds(map["taskSecondsBefore"]),
      confirmedAt: millis(map["confirmedMs"])
    )
  }

  private static func date(_ value: Any?) -> Date? {
    guard let number = value as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: number.doubleValue / 1000)
  }

  private static func millis(_ value: Any?) -> TimeInterval {
    ((value as? NSNumber)?.doubleValue ?? 0) / 1000
  }

  private static func seconds(_ value: Any?) -> TimeInterval {
    (value as? NSNumber)?.doubleValue ?? 0
  }
}
