import ActivityKit
import AppIntents
import Foundation

/// Pause and Resume, as the Lock Screen's own buttons.
///
/// `LiveActivityIntent` rather than a link: a link opens the app, and
/// pausing a timer is not worth unlocking a phone for. The work is the
/// same arithmetic the app does, over the session in the App Group, with
/// no Flutter engine involved — so it does not matter whether the app is
/// running, suspended, or has not been launched since the phone restarted.
///
/// Compiled into the app as well as the extension, because the system
/// decides which process performs the intent and both must be able to
/// name the type.
@available(iOS 17.0, *)
struct PauseSessionIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Pause session"
  static var description = IntentDescription("Pause the running sondr session.")

  /// Not in Shortcuts or Spotlight. It is a button on a card about a
  /// session that is running right now; there is nothing to automate.
  static var isDiscoverable: Bool = false

  init() {}

  func perform() async throws -> some IntentResult {
    await SessionControl.apply(.pause)
    return .result()
  }
}

@available(iOS 17.0, *)
struct ResumeSessionIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Resume session"
  static var description = IntentDescription("Resume the paused sondr session.")
  static var isDiscoverable: Bool = false

  init() {}

  func perform() async throws -> some IntentResult {
    await SessionControl.apply(.resume)
    return .result()
  }
}

/// Changing the session and telling the card about it.
@available(iOS 17.0, *)
enum SessionControl {
  enum Change {
    case pause
    case resume
  }

  /// Read, transform, write, then redraw the card.
  ///
  /// The write comes before the update so the app and the card can never
  /// disagree: whatever is on screen has already been written down, and
  /// the app reads the same bytes the next time it looks.
  ///
  /// Does nothing at all when there is nothing to do — no session, or a
  /// session already in the state being asked for. The card is redrawn
  /// only when something actually changed.
  static func apply(
    _ change: Change,
    now: Date = Date(),
    defaults: UserDefaults? = SessionBox.sharedDefaults
  ) async {
    guard let current = SessionBox.read(from: defaults) else { return }
    let changed = switch change {
    case .pause: SessionMutation.pause(current, at: now)
    case .resume: SessionMutation.resume(current, at: now)
    }
    guard
      let changed,
      SessionBox.write(changed, to: defaults),
      let session = SessionSnapshot.from(changed)
    else { return }

    // Recomputed here too, not just in the app: pausing clears the
    // staleDate, because a paused session is not approaching anything, and
    // resuming has to set a fresh one — the crossing has moved by however
    // long the pause lasted.
    let content = ActivityContent(
      state: SondrActivityAttributes.ContentState(session),
      staleDate: session.staleDate(at: now)
    )
    for activity in Activity<SondrActivityAttributes>.activities {
      await activity.update(content)
    }
  }
}
