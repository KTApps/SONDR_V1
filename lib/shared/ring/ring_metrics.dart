/// Shared ring and progress metrics.
///
/// Two things live here because more than one component needs them to agree:
/// the app's THIN ring weight, and how every progress indicator turns a
/// fraction into a fill.
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

/// What a ring or bar draws for a true progress of [fraction]: the real
/// figure, kept within 0..1. No floor and no ceiling — a first few minutes
/// draw as the sliver they are, and the last minutes before a milestone as
/// nearly closed.
double shownProgress(double fraction) => fraction.clamp(0.0, 1.0);
