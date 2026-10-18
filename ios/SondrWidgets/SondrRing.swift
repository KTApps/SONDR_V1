import SwiftUI
import WidgetKit

/// The milestone ring, filling toward the next twenty hours.
///
/// A running ring is a `ProgressView` over a span of time, not a fraction:
/// that is the one form the system will advance by itself, on the device,
/// with nothing sent to it. A paused ring is a fraction, drawn by hand,
/// because it is not going anywhere.
///
/// The track is drawn underneath in the app's own `ringTrack` grey. The fill
/// is the system's ring, tinted `ringFill` — its stroke width is the
/// system's, not a number this code can set, so the `stroke` below sizes the
/// track and the paused ring only.
struct SondrRing: View {
  let session: SessionSnapshot
  let now: Date
  let diameter: CGFloat
  let stroke: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .stroke(Ink.ringTrack, lineWidth: stroke)
      if session.isPaused {
        Circle()
          .trim(from: 0, to: session.progress(at: now))
          .stroke(
            Ink.ringFill,
            style: StrokeStyle(lineWidth: stroke, lineCap: .butt)
          )
          // Trim starts at three o'clock and runs clockwise; the app's rings
          // all start at twelve.
          .rotationEffect(.degrees(-90))
      } else {
        ProgressView(timerInterval: session.bandRange(at: now), countsDown: false) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(Ink.ringFill)
      }
    }
    .frame(width: diameter, height: diameter)
  }
}
