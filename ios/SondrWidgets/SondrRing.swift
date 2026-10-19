import SwiftUI
import WidgetKit

/// The milestone ring, filling toward the next twenty hours.
///
/// A running ring is a `ProgressView` over a span of time, not a fraction:
/// that is the one form the system will advance by itself, on the device,
/// with nothing sent to it. A paused ring is a fraction, drawn by hand,
/// because it is not going anywhere.
///
/// Both are drawn to the system ring's own geometry, so the two states are
/// the same picture and only the motion differs. The system's circular
/// `ProgressView` takes neither a diameter nor a stroke width: it fills the
/// frame it is given and picks its own. Measured off @3x screenshots on
/// iOS 26, it puts the stroke's OUTER edge on the frame edge and makes the
/// stroke a tenth of the diameter — Ø20 → 2.00, Ø36 → 3.67, Ø48 → 4.3-4.8.
/// Drawing the track at Ø48 with a 5pt stroke, as the design asks, put it
/// outside the fill instead of behind it: a dark outline round a light
/// ring, with nothing to read the progress against.
struct SondrRing: View {
  let session: SessionSnapshot
  let now: Date

  /// The frame the ring fills — 48 on the Lock Screen, 36 expanded, 20
  /// compact. The stroke follows from it; there is no second number,
  /// because the system does not accept one.
  let diameter: CGFloat

  private var stroke: CGFloat { diameter / 10 }

  /// Inset by half a stroke, so the stroke's outer edge lands on the frame
  /// edge — where the system puts its own.
  private var band: some Shape { Circle().inset(by: stroke / 2) }

  var body: some View {
    ZStack {
      band.stroke(Ink.ringTrack, lineWidth: stroke)
      if session.isPaused {
        pausedArc
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

  @ViewBuilder
  private var pausedArc: some View {
    let progress = session.progress(at: now)
    // A round cap on nothing is still a dot, and a session that has just
    // crossed a milestone has nothing to show.
    if progress > 0 {
      band
        .trim(from: 0, to: progress)
        .stroke(
          Ink.ringFill,
          // The system's arc ends are round. A butt cap here would make
          // pausing redraw the ring rather than stop it.
          style: StrokeStyle(lineWidth: stroke, lineCap: .round)
        )
        // Trim starts at three o'clock and runs clockwise; the app's rings
        // all start at twelve.
        .rotationEffect(.degrees(-90))
    }
  }
}
