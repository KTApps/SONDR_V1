import ActivityKit
import AppIntents
import Foundation
import WidgetKit

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
  ///
  /// Idempotent at the level of the request, not only of the arithmetic:
  /// a Pause when already paused, or a Resume when already running,
  /// writes nothing — and still asks the widget to redraw, because the
  /// widget that offered the button is the one showing a state the
  /// session has already left. That is the second tap on a slow widget:
  /// it must not become the first tap undone.
  ///
  /// `reload` is injectable so a test can see it was asked for.
  ///
  /// The instant written is the tap's, not the clock's: see `TapTime`. A
  /// pause can never land before the session started, nor a resume before
  /// the pause it ends.
  static func apply(
    _ change: Change,
    now: Date = Date(),
    launchedAt: Date? = LaunchAnchor.processLaunchedAt,
    defaults: UserDefaults? = SessionBox.sharedDefaults,
    reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
  ) async {
    guard let current = SessionBox.read(from: defaults) else { return }
    let snapshot = SessionSnapshot.from(current)
    let floor: Date? = switch change {
    case .pause: snapshot?.startedAt
    case .resume: snapshot?.pausedAt
    }
    let tap = TapTime.resolve(now: now, launchedAt: launchedAt, notBefore: floor)
    let changed = switch change {
    case .pause: SessionMutation.pause(current, at: tap.stamp)
    case .resume: SessionMutation.resume(current, at: tap.stamp)
    }
    guard let changed else {
      // Already there. The widget is the one that is behind.
      reload()
      return
    }
    guard
      SessionBox.write(changed, to: defaults),
      let session = SessionSnapshot.from(changed)
    else { return }

    // The session moved, so everything showing it is now wrong. The
    // widget first and at once — before the card's updates are awaited —
    // then a running app is told to re-read rather than carry on counting
    // from a clock that has been paused under it.
    reload()
    SessionBroadcast.post()
    IntentTrace.record(
      change == .pause ? "pause" : "resume", performedAt: now, tap, defaults: defaults
    )

    // Never a staleDate — see SessionActivityChannel.content(of:). The
    // card is redrawn from the session at this push and holds until the
    // next one.
    let content = ActivityContent(
      state: SondrActivityAttributes.ContentState(session),
      staleDate: nil
    )
    for activity in Activity<SondrActivityAttributes>.activities {
      await activity.update(content)
    }
  }
}
