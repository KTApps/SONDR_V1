import ActivityKit
import Flutter
import Foundation
import UIKit

/// The app's end of the Lock Screen card.
///
/// A method channel rather than a package: everything drawn on the card is
/// written in Swift in SondrWidgets anyway, so the only thing left for Dart
/// to say is start, change, stop — and the only thing left to answer back is
/// which word someone tapped.
///
/// Nothing here is allowed to matter to the timer. Every path returns quietly
/// on an iPhone that cannot show a card.
final class SessionActivityChannel: NSObject, FlutterSceneLifeCycleDelegate {
  static let shared = SessionActivityChannel()
  static let channelName = "sondr/live_activity"
  static let urlScheme = "sondr"

  private var channel: FlutterMethodChannel?

  /// Taps that arrived before Dart had read the stored session.
  ///
  /// A card tapped while the app was not running launches the app, and the
  /// tap beats the launch. Stopping a session the app has not restored yet
  /// would stop nothing, so the word waits here until Dart says it is
  /// ready.
  private var waiting: [String] = []
  private var listening = false

  private override init() { super.init() }

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    self.channel = channel
    // Flutter's own scene delegate forwards URLs to plugins; this is how to
    // be one of them without replacing a method it implements and does not
    // declare.
    registrar.addSceneDelegate(self)
  }

  // MARK: - Dart asking

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "supported":
      result(Self.canShowCards)

    case "ready":
      listening = true
      let held = waiting
      waiting.removeAll()
      result(nil)
      held.forEach { send($0) }

    case "show":
      guard
        let map = call.arguments as? [String: Any],
        let session = SessionSnapshot.from(map)
      else {
        result(nil)
        return
      }
      if #available(iOS 17.0, *) { show(session) }
      result(nil)

    case "clear":
      if #available(iOS 17.0, *) { clear() }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Whether a card can exist on this phone at all: iOS 17 for the
  /// interactive card, and the Settings switch the owner controls.
  private static var canShowCards: Bool {
    if #available(iOS 17.0, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }

  // MARK: - ActivityKit

  /// The card's content. Never a staleDate: a stale card loses the seconds
  /// off its elapsed clock ("7:--"), measured on device. The card changes
  /// only when something pushes it.
  @available(iOS 17.0, *)
  private static func content(
    of session: SessionSnapshot
  ) -> ActivityContent<SondrActivityAttributes.ContentState> {
    ActivityContent(state: .init(session), staleDate: nil)
  }

  /// The one push nobody makes: a minute before the crossing.
  ///
  /// Every other push — start, pause, resume, foreground — is caused by a
  /// person. If nobody touches the phone for the last minute, the running
  /// countdown would reach zero and turn round. So while the app is in the
  /// foreground, one update is booked for a minute out, which redraws the
  /// card with its fixed last-minute line. Rebooked on every push, because
  /// the crossing moves with paused time; dropped on clear.
  ///
  /// If the app is suspended before it fires, it does not fire — the line
  /// may then count up briefly until the next push. Accepted.
  private let lastMinute = ScheduledUpdate()

  @available(iOS 17.0, *)
  private func bookLastMinute(for session: SessionSnapshot) {
    lastMinute.cancel()
    guard let at = session.staticLineFireDate(at: Date()) else { return }
    lastMinute.schedule(at: at) { [weak self] in
      // The stored session is the truth; this one may be a minute stale.
      guard let self, let current = SessionSnapshot.current(), !current.isPaused
      else { return }
      let content = Self.content(of: current)
      for activity in Activity<SondrActivityAttributes>.activities {
        await activity.update(content)
      }
    }
  }

  /// Put the session on the Lock Screen, starting a card if there is none.
  ///
  /// Which of the two it is, is ActivityKit's to answer, not Dart's: the app
  /// can be relaunched into a session that already has a card, and asking
  /// Dart to remember across process deaths would be asking it to guess.
  ///
  /// The task name is static — an activity cannot be renamed — so a card
  /// naming a different task is ended and asked for again. That happens
  /// exactly once, when a session that started before the task list had
  /// loaded learns what it is for.
  @available(iOS 17.0, *)
  private func show(_ session: SessionSnapshot) {
    let name = session.taskName ?? ""
    let content = Self.content(of: session)
    bookLastMinute(for: session)
    Task {
      let existing = Activity<SondrActivityAttributes>.activities
      let mine = existing.filter { $0.attributes.taskName == name }
      if mine.isEmpty {
        for activity in existing {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
          attributes: SondrActivityAttributes(taskName: name),
          content: content,
          pushType: nil
        )
      } else {
        for activity in mine { await activity.update(content) }
      }
    }
  }

  /// Take every card away now. `.immediate` because a card still saying
  /// "Pause" after the session is over is a lie on the Lock Screen.
  @available(iOS 17.0, *)
  private func clear() {
    lastMinute.cancel()
    Task {
      for activity in Activity<SondrActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  // MARK: - Taps coming back

  /// `sondr://stop` becomes `stop`. Anything else is somebody else's URL.
  private func accept(_ urls: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in urls {
      let url = context.url
      guard url.scheme == Self.urlScheme, let action = url.host, !action.isEmpty
      else { continue }
      handled = true
      if listening { send(action) } else { waiting.append(action) }
    }
    return handled
  }

  private func send(_ action: String) {
    channel?.invokeMethod("link", arguments: action)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    accept(URLContexts)
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let urls = connectionOptions?.urlContexts else { return false }
    return accept(urls)
  }
}
