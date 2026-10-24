import Foundation

/// One task, as the Home Screen widget draws it.
///
/// Mirrors `WidgetTask` in lib/features/widget/widget_snapshot.dart. The
/// two processes never talk: these field names and units are the whole
/// agreement, so a change here is a change there.
struct WidgetTask: Equatable, Identifiable {
  let id: String
  let name: String

  /// Seconds today, and over the task's life.
  let today: Int
  let total: Int

  /// 0..1 toward the next twenty hours.
  let progress: Double

  /// The last day with time on it, as a day key ('' if never). What the
  /// Automatic list is ordered by.
  let lastTracked: String

  init(
    id: String,
    name: String,
    today: Int = 0,
    total: Int = 0,
    progress: Double = 0,
    lastTracked: String = ""
  ) {
    self.id = id
    self.name = name
    self.today = today
    self.total = total
    self.progress = progress
    self.lastTracked = lastTracked
  }

  init?(_ map: [String: Any]) {
    guard let id = map["id"] as? String, let name = map["name"] as? String
    else { return nil }
    self.id = id
    self.name = name
    today = map["today"] as? Int ?? 0
    total = map["total"] as? Int ?? 0
    progress = map["progress"] as? Double ?? 0
    lastTracked = map["last"] as? String ?? ""
  }

  /// A completed milestone reads white; one still being filled reads grey.
  /// Progress resets to zero at each milestone, so "complete" is the
  /// instant before the reset and never a resting state — see
  /// `Task.milestoneProgress`.
  var isMilestoneComplete: Bool { progress >= 1 }
}

/// Everything the widget draws, read out of the App Group.
///
/// Written by the app (see widget_snapshot.dart) whenever a task, the
/// selection or today's habits change. The running session is NOT in
/// here: that is `sondr.session`, read separately, because there is only
/// one clock.
struct WidgetSnapshot: Equatable {
  static let key = "sondr.widget"
  static let appGroup = SessionSnapshot.appGroup

  let tasks: [WidgetTask]

  /// Today's seconds per task, in the same order as `tasks` — Home's dial.
  let segments: [Int]
  let habitsDone: Int
  let habitsTotal: Int

  /// What Home has selected, or "" for the collective view.
  let selectedTaskId: String

  init(
    tasks: [WidgetTask] = [],
    segments: [Int] = [],
    habitsDone: Int = 0,
    habitsTotal: Int = 0,
    selectedTaskId: String = ""
  ) {
    self.tasks = tasks
    self.segments = segments
    self.habitsDone = habitsDone
    self.habitsTotal = habitsTotal
    self.selectedTaskId = selectedTaskId
  }

  /// Decode the document, or nothing if it is absent or malformed. A
  /// widget with nothing to read draws the empty state, which is also
  /// what a guest sees.
  static func from(_ json: String?) -> WidgetSnapshot? {
    guard
      let json,
      let data = json.data(using: .utf8),
      let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    let raw = map["tasks"] as? [[String: Any]] ?? []
    return WidgetSnapshot(
      tasks: raw.compactMap(WidgetTask.init),
      segments: (map["segments"] as? [Int]) ?? [],
      habitsDone: map["habitsDone"] as? Int ?? 0,
      habitsTotal: map["habitsTotal"] as? Int ?? 0,
      selectedTaskId: map["selected"] as? String ?? ""
    )
  }

  static func read(
    from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)
  ) -> WidgetSnapshot? {
    from(defaults?.string(forKey: key))
  }

  /// The task the app has selected, or the first one.
  var selected: WidgetTask? {
    tasks.first { $0.id == selectedTaskId } ?? tasks.first
  }

  func task(_ id: String) -> WidgetTask? { tasks.first { $0.id == id } }
}

/// Which tasks one widget shows, and in what order.
///
/// Automatic means the five most recently tracked, which is what a glance
/// at a Home Screen is for. A chosen list is kept exactly as chosen —
/// including its order — and capped at five, because a sixth row does not
/// fit a medium widget and a sixth dot does not read on a small one.
enum WidgetList {
  static let maximum = 5

  static func automatic(_ tasks: [WidgetTask], limit: Int = maximum) -> [WidgetTask] {
    tasks
      .sorted { a, b in
        // Most recently tracked first; a tie, or two never tracked, keeps
        // the app's own order, which is what `enumerated` preserves.
        a.lastTracked == b.lastTracked
          ? false
          : a.lastTracked > b.lastTracked
      }
      .prefix(limit)
      .map { $0 }
  }

  /// A chosen list, resolved against what still exists. A task deleted in
  /// the app simply drops out rather than leaving a hole.
  static func chosen(
    _ ids: [String],
    from snapshot: WidgetSnapshot,
    limit: Int = maximum
  ) -> [WidgetTask] {
    ids.compactMap(snapshot.task).prefix(limit).map { $0 }
  }

  /// The one after `current`, wrapping. A list of one has nowhere to go.
  static func next(after current: String, in list: [WidgetTask]) -> WidgetTask? {
    guard list.count > 1 else { return nil }
    let index = list.firstIndex { $0.id == current } ?? -1
    return list[(index + 1) % list.count]
  }
}

/// The outer band of Home's dial: which tasks get a slice, where each
/// slice begins, and the turn that brings the selected one to 12.
///
/// Home's own arithmetic, from lib/shared/ring/dial_geometry.dart, said
/// in turns rather than radians (one turn is 2π, which is the unit
/// SwiftUI trims in). The slits come out of the circle first and what is
/// left is split by weight; then the whole band is turned by the
/// selected slice's own start, so that slice opens at 12 and every
/// boundary behind it is pinned rather than sliding backwards while a
/// session runs.
enum DialBand {
  /// The tasks with time today, keeping the place they have in the
  /// snapshot. A task with nothing today has no slice at all — Home
  /// drops it rather than drawing a slice of zero.
  static func entries(_ snapshot: WidgetSnapshot) -> [(index: Int, seconds: Int)] {
    snapshot.tasks.indices.compactMap { i in
      let seconds = i < snapshot.segments.count ? snapshot.segments[i] : 0
      return seconds > 0 ? (index: i, seconds: seconds) : nil
    }
  }

  /// Where each slice begins, clockwise from 12, as a fraction of a
  /// turn. `slit` is the gap between slices in the same unit.
  static func starts(weights: [Double], slit: Double) -> [Double] {
    guard !weights.isEmpty else { return [] }
    let total = weights.reduce(0, +)
    guard total > 0 else { return Array(repeating: 0, count: weights.count) }
    let available = 1 - slit * Double(weights.count)
    var cursor = 0.0
    var out: [Double] = []
    for weight in weights {
      out.append(cursor)
      cursor += (weight / total) * available + slit
    }
    return out
  }

  /// How much of a slice there is to draw, in turns.
  static func sweeps(weights: [Double], slit: Double) -> [Double] {
    let total = weights.reduce(0, +)
    guard total > 0 else { return Array(repeating: 0, count: weights.count) }
    let available = 1 - slit * Double(weights.count)
    return weights.map { ($0 / total) * available }
  }

  /// The turn that puts `selected` at 12. Nothing when it has no slice,
  /// which is Home's answer too (`_targetRotation` returns 0).
  static func rotation(starts: [Double], selected: Int?) -> Double {
    guard let selected, selected >= 0, selected < starts.count else { return 0 }
    return starts[selected]
  }
}

/// What the primary control says, and what a screen reader hears.
///
/// One definition for the Home Screen widget, the Lock Screen card and
/// the Dynamic Island, so the three cannot drift apart. The app says the
/// same words in lib/features/timer/timer_screen.dart, and a test reads
/// both files to keep it that way.
enum PrimaryWord {
  static let start = "Start"
  static let pause = "Pause"

  /// Going again after a pause reads "Start" — that is the word for it —
  /// and is spoken "Resume", because that is what it does.
  static let resumeSpoken = "Resume"

  static func label(hasSession: Bool, isPaused: Bool) -> String {
    hasSession && !isPaused ? pause : start
  }

  static func spoken(hasSession: Bool, isPaused: Bool) -> String {
    hasSession && isPaused
      ? resumeSpoken
      : label(hasSession: hasSession, isPaused: isPaused)
  }
}
