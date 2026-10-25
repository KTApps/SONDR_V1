import ActivityKit
import AppIntents
import Foundation
import WidgetKit

/// A task, as the widget's own configuration names it.
@available(iOS 17.0, *)
struct TaskEntity: AppEntity, Identifiable {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
  static var defaultQuery = TaskQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

/// Where Edit Widget's task list comes from: the App Group snapshot the
/// app keeps up to date, which is the only thing an extension can read
/// without a network.
@available(iOS 17.0, *)
struct TaskQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [TaskEntity] {
    let snapshot = WidgetSnapshot.read() ?? WidgetSnapshot()
    return identifiers.compactMap { id in
      snapshot.task(id).map { TaskEntity(id: $0.id, name: $0.name) }
    }
  }

  func suggestedEntities() async throws -> [TaskEntity] {
    let snapshot = WidgetSnapshot.read() ?? WidgetSnapshot()
    return snapshot.tasks.map { TaskEntity(id: $0.id, name: $0.name) }
  }
}

/// What one widget on one Home Screen is set to show.
///
/// Empty means Automatic: the five most recently tracked. Each instance
/// keeps its own list, which is what an AppIntentConfiguration is for.
@available(iOS 17.0, *)
struct TasksConfiguration: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Tasks"
  // One literal: IntentDescription takes a LocalizedStringResource, and
  // a concatenation is not one.
  static var description = IntentDescription(
    "Choose up to five tasks, or leave empty for the five most recent."
  )

  @Parameter(title: "Tasks")
  var tasks: [TaskEntity]?

  init() {}

  init(tasks: [TaskEntity]?) { self.tasks = tasks }

  /// The ids this instance was configured with, in order.
  var chosenIds: [String] { (tasks ?? []).map(\.id) }
}

/// Writing the app's selection from a widget.
///
/// The selection lives in the snapshot the app wrote, so changing it from
/// here means rewriting that document — the app reads it back on its next
/// launch, and the widget redraws from it immediately. The app's own
/// selection provider reads the same id at startup.
@available(iOS 17.0, *)
enum WidgetSelection {
  static let key = "sondr.widgetSelection"

  /// Record a new selection where both sides can see it.
  ///
  /// Two writes rather than one: the snapshot so the widget redraws now,
  /// and a small separate key the app reads at launch, because the app
  /// rewrites the whole snapshot whenever anything changes and must not
  /// race with this.
  ///
  /// Refused while a session is on. The task being tracked is the task
  /// shown, everywhere, until it ends — so cycling a small widget and
  /// tapping a medium's row do nothing, and the gate is here rather than
  /// in the two intents so nothing can get past it. Starting a session
  /// selects its own task first, before the session is written down.
  static func set(
    _ taskId: String,
    defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)
  ) {
    guard let defaults, SessionBox.read(from: defaults) == nil else { return }
    defaults.set(taskId, forKey: key)
    guard
      let json = defaults.string(forKey: WidgetSnapshot.key),
      let data = json.data(using: .utf8),
      var map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return }
    map["selected"] = taskId
    guard let out = try? JSONSerialization.data(withJSONObject: map) else { return }
    defaults.set(String(decoding: out, as: UTF8.self), forKey: WidgetSnapshot.key)
  }

  /// What a widget asked for since the app last looked, if anything.
  static func pending(
    defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)
  ) -> String? {
    defaults?.string(forKey: key)
  }

  static func clear(
    defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)
  ) {
    defaults?.removeObject(forKey: key)
  }
}

/// Tapping the task name on a small widget: show the next task in this
/// widget's list, and make it the app's selection too.
@available(iOS 17.0, *)
struct CycleTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Next task"
  static var isDiscoverable: Bool = false

  @Parameter(title: "Tasks")
  var ids: [String]

  @Parameter(title: "Current")
  var current: String

  init() {
    ids = []
    current = ""
  }

  init(ids: [String], current: String) {
    self.ids = ids
    self.current = current
  }

  func perform() async throws -> some IntentResult {
    let snapshot = WidgetSnapshot.read() ?? WidgetSnapshot()
    let list = ids.isEmpty
      ? WidgetList.automatic(snapshot.tasks)
      : WidgetList.chosen(ids, from: snapshot)
    if let next = WidgetList.next(after: current, in: list) {
      WidgetSelection.set(next.id)
      WidgetCenter.shared.reloadAllTimelines()
    }
    return .result()
  }
}

/// Tapping a row on a medium widget: select that task.
@available(iOS 17.0, *)
struct SelectTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Select task"
  static var isDiscoverable: Bool = false

  @Parameter(title: "Task")
  var id: String

  init() { id = "" }

  init(id: String) { self.id = id }

  func perform() async throws -> some IntentResult {
    guard !id.isEmpty else { return .result() }
    WidgetSelection.set(id)
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}

/// Stop, asked for from the Home Screen widget.
///
/// Stopping needs the app — the camera, the milestone, the post — so the
/// widget cannot do it; it can only ask. The Lock Screen card asks with a
/// link, but a widget's Button cannot open a custom URL scheme
/// (OpenURLIntent takes universal links only, so sondr://stop did
/// nothing). This is the other way: a flag in the App Group, and an
/// intent that opens the app. SessionActivityChannel takes the flag when
/// the scene becomes active and feeds "stop" into the very path the
/// card's link takes, hold-back included.
enum PendingStop {
  static let key = "sondr.pendingStop"

  static func set(
    defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)
  ) {
    defaults?.set(true, forKey: key)
  }

  /// Whether a stop is waiting, clearing it either way. Taken once: a
  /// stop that is acted on twice would stop the next session too.
  ///
  /// A flag with no session behind it is cleared and ignored — the
  /// session ended some other way before the app got here.
  static func take(
    defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)
  ) -> Bool {
    guard let defaults, defaults.bool(forKey: key) else { return false }
    defaults.removeObject(forKey: key)
    return SessionBox.read(from: defaults) != nil
  }
}

@available(iOS 17.0, *)
struct StopSessionIntent: AppIntent {
  static var title: LocalizedStringResource = "Stop session"
  static var description = IntentDescription("Stop the running sondr session.")
  static var isDiscoverable: Bool = false

  /// The whole point: the app comes to the front and finishes the
  /// session.
  static var openAppWhenRun: Bool = true

  init() {}

  func perform() async throws -> some IntentResult {
    PendingStop.set()
    return .result()
  }
}

/// Start a session on a task, from the Home Screen, without opening the
/// app.
///
/// `LiveActivityIntent` is what makes that legal. ActivityKit's own
/// documentation: a Live Activity cannot be started while the app is in
/// the background "unless you adopt AppIntents and start the Live
/// Activity using a LiveActivityIntent" — the system performs those in
/// the app's process. Pause and Resume already work this way.
///
/// The session is written to the App Group FIRST and the card requested
/// second, so the app and the card can never disagree: whatever is on
/// screen has already been written down, and the app reads the same bytes
/// the next time it looks.
@available(iOS 17.0, *)
struct StartSessionIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Start session"
  static var description = IntentDescription("Start tracking a task.")
  static var isDiscoverable: Bool = false

  @Parameter(title: "Task")
  var id: String

  init() { id = "" }

  init(id: String) { self.id = id }

  func perform() async throws -> some IntentResult {
    await SessionStart.begin(taskId: id)
    return .result()
  }
}

/// Beginning a session where the app would have begun one.
@available(iOS 17.0, *)
enum SessionStart {
  /// The session document, in the shape Dart writes and Swift reads —
  /// epoch milliseconds for the times, seconds for the task's total. See
  /// SessionSnapshot.from and lib/features/timer/session_store.dart.
  static func document(
    taskId: String,
    taskName: String,
    taskSecondsBefore: Int,
    startedAt: Date
  ) -> [String: Any] {
    [
      "startedAt": Int(startedAt.timeIntervalSince1970 * 1000),
      "pausedMs": 0,
      "taskId": taskId,
      "taskName": taskName,
      "taskSecondsBefore": taskSecondsBefore,
      "confirmedMs": 0,
    ]
  }

  /// Does nothing when a session is already running: two sessions is a
  /// state the app cannot represent, and by then the widget's own button
  /// reads "Stop" anyway.
  ///
  /// Returns whether it started one, so the tests can say so without a
  /// card.
  @discardableResult
  static func begin(
    taskId: String,
    now: Date = Date(),
    defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup),
    requestCard: Bool = true
  ) async -> Bool {
    guard SessionBox.read(from: defaults) == nil else { return false }
    let snapshot = WidgetSnapshot.read(from: defaults) ?? WidgetSnapshot()
    guard let task = snapshot.task(taskId) ?? snapshot.selected else {
      return false
    }

    let session = document(
      taskId: task.id,
      taskName: task.name,
      taskSecondsBefore: task.total,
      startedAt: now
    )
    // The selection first: once the session is written down nothing may
    // change which task is shown, this included.
    WidgetSelection.set(task.id, defaults: defaults)
    guard SessionBox.write(session, to: defaults) else { return false }

    // One rule, everywhere the extension writes a session: redraw the
    // widget, and tell the app.
    WidgetCenter.shared.reloadAllTimelines()
    SessionBroadcast.post()

    guard requestCard else { return true }
    guard
      ActivityAuthorizationInfo().areActivitiesEnabled,
      let decoded = SessionSnapshot.from(session)
    else { return true }
    // Never a staleDate — see SessionActivityChannel.content(of:).
    let content = ActivityContent(
      state: SondrActivityAttributes.ContentState(decoded),
      staleDate: nil
    )
    _ = try? Activity.request(
      attributes: SondrActivityAttributes(taskName: task.name),
      content: content
    )
    return true
  }
}
