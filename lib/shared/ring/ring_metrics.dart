/// Shared ring and progress metrics.
///
/// Two things live here because more than one component needs them to agree:
/// the app's THIN ring weight, and the clamp every progress indicator draws
/// through. A ring and a bar that disagreed about what "nearly done" looks
/// like would be two different promises about the same number.
library;

/// The app's ONE ring weight, in reference points.
///
/// Every ring in the app is drawn at this: the day dials on Home, the
/// profile's in-progress rings, the Milestones page's completed rings. It is
/// a fixed weight rather than a fraction of each ring's diameter, because a
/// ratio makes a small ring a thin ring — the Ø40 band rings came out at 2.1
/// against the day dials' 7, and they read as a different component rather
/// than the same one drawn smaller.
///
/// A WEIGHT, so it does not scale with diameter. It does scale with the
/// screen: multiply by `figmaScale` at the point of use, like every other
/// number in this app.
const double kRingStroke = 7;

/// The day dial's reference diameter, which is where [kRingStroke] was set.
///
/// [kRingStroke] / [kCompactDialSize] is the ratio SegmentedDial draws its
/// compact bands at, so the dials and the rings cannot drift apart: change
/// the weight here and both move together.
const double kCompactDialSize = 57;

/// The ratio a compact day dial strokes its bands at.
const double kCompactDialStrokeRatio = kRingStroke / kCompactDialSize;

/// The app's ring stroke at this screen's [scale].
double ringStroke(double scale) => kRingStroke * scale;

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
