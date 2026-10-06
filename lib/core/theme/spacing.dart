/// Sondr's three spacing tiers (see DESIGN.md).
///
/// Multiply by `figmaScale(context)` at the point of use — these are the
/// reference-canvas values, like every other measurement in the app.
library;

/// Binds a label to its value; below base by design.
const double kSpacingPair = kSpacingBase / 2;

/// Rhythm WITHIN a group: between rows of a list, between the items of one
/// block. Tighter than this belongs to [kSpacingPair].
const double kSpacingBase = 12;

/// Separation BETWEEN zones of a screen — on Profile, between the stats, the
/// doorways, the in-progress strip and the account footer. Twice the base, so
/// the tiers read as clearly different rather than as a nudge.
///
/// This is also the ceiling: no vertical gap in the app exceeds it. Screens
/// that need to fill space use a flexible spacer, never a bigger gap.
const double kSpacingSection = kSpacingBase * 2;
