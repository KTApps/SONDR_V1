import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Where a tap on the card goes.
///
/// The extension cannot run the app's code, so every control is a link back
/// into it. The app registers `sondr` as a URL scheme and routes these.
enum SondrLink {
  static let home = URL(string: "sondr://home")!
  static let stop = URL(string: "sondr://stop")!

  /// Pause and Resume are buttons now, handled in place by an intent.
  /// These stay registered and handled by the app as the fallback route —
  /// nothing on the card uses them.
  static let pause = URL(string: "sondr://pause")!
  static let resume = URL(string: "sondr://resume")!
}

/// The running session, on the Lock Screen and in the Dynamic Island.
struct SondrSessionActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SondrActivityAttributes.self) { context in
      LockScreenCard(
        taskName: context.attributes.taskName,
        state: context.state,
        isStale: context.isStale
      )
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .widgetURL(SondrLink.home)
      .activityBackgroundTint(Ink.background)
      .activitySystemActionForegroundColor(Ink.primary)
    } dynamicIsland: { context in
      let session = context.state.session
      let now = Date()
      let display = MilestoneDisplay.state(
        for: session,
        at: now,
        isStale: context.isStale
      )
      let name = taskLine(context.attributes.taskName, session.isPaused)
      return DynamicIsland {
        // The ring on its own. Sharing the leading region with the task
        // name left the name about forty points wide, so "Learn piano"
        // arrived as "Learn…".
        DynamicIslandExpandedRegion(.leading) {
          SondrRing(session: session, now: now, diameter: 36, display: display)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Elapsed(session: session, size: 24)
            .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
        }
        // The name goes in the bottom region, not the centre one. The
        // centre sits between the ring and the clock, which left it about
        // forty points wide — and filling it made the system drop every
        // region but the leading one. Here it gets the full width of the
        // island, which is what "its own line" has to mean.
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 10) {
            Text(name)
              .font(.inter(13, .semibold))
              .foregroundStyle(Ink.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
            HStack(spacing: 48) {
              Actions(isPaused: session.isPaused)
            }
          }
          .frame(maxWidth: .infinity)
        }
      } compactLeading: {
        SondrRing(session: session, now: now, diameter: 20, display: display)
      } compactTrailing: {
        Elapsed(session: session, size: 13)
          .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
      } minimal: {
        SondrRing(session: session, now: now, diameter: 20, display: display)
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

  /// The system's own answer to "has the staleDate passed?". The only
  /// signal available when nothing has woken up since the crossing.
  let isStale: Bool

  var body: some View {
    let session = state.session
    let now = Date()
    let display = MilestoneDisplay.state(for: session, at: now, isStale: isStale)
    HStack(spacing: 12) {
      SondrRing(session: session, now: now, diameter: 48, display: display)
      VStack(alignment: .leading, spacing: 6) {
        Text(taskLine(taskName, session.isPaused))
          .font(.inter(13, .semibold))
          .foregroundStyle(Ink.secondary)
          .lineLimit(1)
        Elapsed(session: session, size: 30)
          .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
        MilestoneLine(session: session, now: now, display: display)
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
///
/// The first is a button, not a link: it runs an intent in place and the
/// card redraws without the app being opened. Stop stays a link, because
/// stopping is the start of the celebration, the camera and the review —
/// all of which need the app.
private struct Actions: View {
  let isPaused: Bool

  var body: some View {
    if isPaused {
      Button(intent: ResumeSessionIntent()) { Primary(word: "Resume") }
        .buttonStyle(.plain)
    } else {
      Button(intent: PauseSessionIntent()) { Primary(word: "Pause") }
        .buttonStyle(.plain)
    }
    Link(destination: SondrLink.stop) {
      Text("Stop")
        .font(.inter(14, .regular))
        .foregroundStyle(Ink.secondary)
    }
  }
}

private struct Primary: View {
  let word: String

  var body: some View {
    Text(word)
      .font(.inter(14, .bold))
      .foregroundStyle(Ink.primary)
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
      // The clock must never wrap: in the expanded island it shares a row
      // with the task name, and without this it folded into "52" / ":0" /
      // "0".
      .lineLimit(1)
  }
}

/// "… to your next milestone", or "You've reached a milestone".
///
/// While the session runs the remaining time is handed to the system as a
/// date, because that is the only countdown that keeps moving without the
/// app being woken to retype it. The system picks the wording.
///
/// A paused card has to write the line itself, and has to write it the
/// system's way: pausing must stop the clock, not reword the sentence
/// under it.
///
/// Once the milestone is reached the sentence changes, and the same 11pt
/// tertiary line says so. Without that, the relative countdown passes zero
/// and counts back up.
private struct MilestoneLine: View {
  let session: SessionSnapshot
  let now: Date
  let display: MilestoneDisplay

  var body: some View {
    Group {
      switch display {
      case .crossed:
        Text(MilestoneDisplay.reachedMessage)
      case .counting(let remaining):
        if session.isPaused {
          Text("\(MilestoneWording.remaining(remaining)) to your next milestone")
        } else {
          // Handed over as a date, not a string, because that is the only
          // countdown that keeps moving without the app being woken to
          // retype it. It can no longer run past zero: the activity's
          // staleDate is this same instant, so the system redraws here.
          Text(
            "\(Text(session.projectedMilestoneDate(at: now), style: .relative)) to your next milestone"
          )
        }
      }
    }
    .font(.inter(11, .regular))
    .foregroundStyle(Ink.tertiary)
    .lineLimit(1)
  }
}
