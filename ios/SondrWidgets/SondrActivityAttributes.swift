import ActivityKit
import Foundation

/// Where a tap on the card or the widget goes.
///
/// The extension cannot run the app's code, so every control that needs
/// the app is a link back into it. The app registers `sondr` as a URL
/// scheme and routes these.
///
/// Here rather than beside the card because the Home Screen widget and
/// the tests need them too, and one list of them is the point.
enum SondrLink {
  static let home = URL(string: "sondr://home")!
  static let stop = URL(string: "sondr://stop")!

  /// Pause and Resume are buttons now, handled in place by an intent.
  /// These stay registered and handled by the app as the fallback route —
  /// nothing on the card uses them.
  static let pause = URL(string: "sondr://pause")!
  static let resume = URL(string: "sondr://resume")!
}

/// What the Live Activity is told about a session.
///
/// Compiled into both the app, which starts and updates the activity, and the
/// extension, which draws it — one source, so the two cannot disagree about
/// the shape.
///
/// The state is the session itself, not a rendered string: the extension is
/// given timestamps and does its own arithmetic, which is what lets the card
/// count on the device with nothing pushed to it.
@available(iOS 17.0, *)
struct SondrActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var startedAt: Date
    var pausedMs: Int
    var pausedAt: Date?
    var taskSecondsBefore: Int
  }

  /// The task the session is for. Static: a session cannot change task
  /// while it runs.
  var taskName: String
}

@available(iOS 17.0, *)
extension SondrActivityAttributes.ContentState {
  /// The same session, with the arithmetic attached.
  ///
  /// The maths lives in one place for both ways the extension can learn
  /// about a session — pushed here as state, or read out of the App Group.
  var session: SessionSnapshot {
    SessionSnapshot(
      startedAt: startedAt,
      pausedTotal: Double(pausedMs) / 1000,
      pausedAt: pausedAt,
      taskSecondsBefore: Double(taskSecondsBefore)
    )
  }

  /// The other direction: a session on its way to the card.
  ///
  /// Shared, because three places now push one — the app when the timer
  /// changes, and each of the two buttons on the card itself.
  init(_ session: SessionSnapshot) {
    self.init(
      startedAt: session.startedAt,
      pausedMs: Int((session.pausedTotal * 1000).rounded()),
      pausedAt: session.pausedAt,
      taskSecondsBefore: Int(session.taskSecondsBefore.rounded())
    )
  }
}
