import ActivityKit
import SwiftUI
import WidgetKit

/// Where a tap on the card goes.
///
/// The extension cannot run the app's code, so every control is a link back
/// into it. The app registers `sondr` as a URL scheme and routes these.
enum SondrLink {
  static let home = URL(string: "sondr://home")!
  static let pause = URL(string: "sondr://pause")!
  static let resume = URL(string: "sondr://resume")!
  static let stop = URL(string: "sondr://stop")!
}

/// The running session, on the Lock Screen and in the Dynamic Island.
struct SondrSessionActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SondrActivityAttributes.self) { context in
      LockScreenCard(
        taskName: context.attributes.taskName,
        state: context.state
      )
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .widgetURL(SondrLink.home)
      .activityBackgroundTint(Ink.background)
      .activitySystemActionForegroundColor(Ink.primary)
    } dynamicIsland: { context in
      let session = context.state.session
      let now = Date()
      let name = taskLine(context.attributes.taskName, session.isPaused)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 12) {
            SondrRing(session: session, now: now, diameter: 36, stroke: 4)
            Text(name)
              .font(.inter(13, .semibold))
              .foregroundStyle(Ink.secondary)
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Elapsed(session: session, size: 24)
            .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 48) {
            Actions(isPaused: session.isPaused)
          }
          .frame(maxWidth: .infinity)
        }
      } compactLeading: {
        SondrRing(session: session, now: now, diameter: 20, stroke: 2.5)
      } compactTrailing: {
        Elapsed(session: session, size: 13)
          .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
      } minimal: {
        SondrRing(session: session, now: now, diameter: 20, stroke: 2.5)
      }
    }
  }
}

/// "Learn piano", or "Learn piano · Paused".
private func taskLine(_ name: String, _ isPaused: Bool) -> String {
  isPaused ? "\(name) · Paused" : name
}

/// The Lock Screen card: ring, what the session is and how long it has run,
/// and the two things worth doing to it.
private struct LockScreenCard: View {
  let taskName: String
  let state: SondrActivityAttributes.ContentState

  var body: some View {
    let session = state.session
    let now = Date()
    HStack(spacing: 12) {
      SondrRing(session: session, now: now, diameter: 48, stroke: 5)
      VStack(alignment: .leading, spacing: 6) {
        Text(taskLine(taskName, session.isPaused))
          .font(.inter(13, .semibold))
          .foregroundStyle(Ink.secondary)
          .lineLimit(1)
        Elapsed(session: session, size: 30)
          .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
        MilestoneLine(session: session, now: now)
      }
      Spacer(minLength: 0)
      VStack(alignment: .trailing, spacing: 10) {
        Actions(isPaused: session.isPaused)
      }
    }
  }
}

/// Pause or Resume, and Stop. The same two words and weights wherever the
/// card appears.
private struct Actions: View {
  let isPaused: Bool

  var body: some View {
    Link(destination: isPaused ? SondrLink.resume : SondrLink.pause) {
      Text(isPaused ? "Resume" : "Pause")
        .font(.inter(14, .bold))
        .foregroundStyle(Ink.primary)
    }
    Link(destination: SondrLink.stop) {
      Text("Stop")
        .font(.inter(14, .regular))
        .foregroundStyle(Ink.secondary)
    }
  }
}

/// How long the session has run, counted by the system.
///
/// `Text(timerInterval:)` is given the instant the reading was zero and left
/// alone: it advances once a second on the device, in a process this app
/// does not have to wake. `pauseTime` freezes it where the pause happened,
/// so a paused card needs no second code path.
private struct Elapsed: View {
  let session: SessionSnapshot
  let size: CGFloat

  /// No session runs for a year. The upper bound only has to be out of the
  /// way.
  private static let horizon: TimeInterval = 365 * 24 * 60 * 60

  var body: some View {
    let from = session.countingFrom
    let window = from...from.addingTimeInterval(Self.horizon)
    return Text(timerInterval: window, pauseTime: session.pausedAt, countsDown: false)
      .font(.inter(size, .bold))
      .monospacedDigit()
  }
}

/// "… to your next milestone".
///
/// While the session runs the remaining time is handed to the system as a
/// date, because that is the only countdown that keeps moving without the
/// app being woken to retype it. The system picks the wording — "3 hr, 12
/// min" — so a running card reads its way and a paused one, which is not
/// going anywhere and can be written out properly, reads "3h 12m".
private struct MilestoneLine: View {
  let session: SessionSnapshot
  let now: Date

  var body: some View {
    Group {
      if session.isPaused {
        Text("\(Self.spelled(session.remaining(at: now))) to your next milestone")
      } else {
        Text(
          "\(Text(session.milestoneDate(at: now), style: .relative)) to your next milestone"
        )
      }
    }
    .font(.inter(11, .regular))
    .foregroundStyle(Ink.tertiary)
    .lineLimit(1)
  }

  static func spelled(_ remaining: TimeInterval) -> String {
    let total = Int(remaining.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
  }
}
