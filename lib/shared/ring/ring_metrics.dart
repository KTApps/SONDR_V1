/// Shared ring and progress metrics.
///
/// Two things live here because more than one component needs them to agree:
/// the app's THIN ring weight, and the clamp every progress indicator draws
/// through. A ring and a bar that disagreed about what "nearly done" looks
/// like would be two different promises about the same number.
library;

/// Stroke as a fraction of diameter for the thin rings — the profile's
/// in-progress rings and the Milestones page's completed rings. Ø56 → 3.
///
/// Stated as a ratio rather than a number so the weight holds at the other
/// diameters these rings appear at (a band ring at Ø40 takes ≈2.1).
const double kThinRingStrokeRatio = 3 / 56;

/// The thin stroke for a ring of [diameter].
double thinRingStroke(double diameter) => diameter * kThinRingStrokeRatio;

/// The smallest fraction that is ever DRAWN for nonzero progress.
///
/// A 20-hour band makes the first half-hour 2.5% of a ring — thinner than the
/// stroke, so it rendered as nothing and the first session of a task looked
/// like no session at all.
const double kProgressFloor = 0.04;

/// The largest fraction that is ever drawn, however close the real figure is.
///
/// A ring drawn at 1.0 is closed, and a closed ring means a milestone REACHED
/// — which is the white ring on the Milestones page, not this one. Holding a
/// visible gap keeps "nearly there" and "there" from looking the same.
const double kProgressCeiling = 0.95;

/// What a ring or bar actually draws for a true progress of [fraction].
///
/// Zero stays zero: an untouched band is an empty track, not a sliver. Above
/// zero it is clamped into [kProgressFloor]..[kProgressCeiling], so any time
/// at all registers and nothing ever reads as finished before it is.
double shownProgress(double fraction) {
  if (fraction <= 0) return 0;
  return fraction.clamp(kProgressFloor, kProgressCeiling);
}
