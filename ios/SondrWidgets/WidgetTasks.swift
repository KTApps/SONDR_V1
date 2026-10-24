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
