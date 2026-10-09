/// Home's vertical skeleton, in Figma reference units measured from the TOP OF
/// THE SCREEN.
///
/// Home and Profile both position globally — no `SafeArea`, no app bar — so a
/// y here is the same y there. Profile lays its own elements on these exact
/// lines: the title, the dial band, the supporting line and the first
/// full-width block land at the same height on both tabs, so moving between
/// them reads as one page changing its contents rather than two different
/// pages.
///
/// Stated once so the two cannot drift. Changing a number here moves BOTH
/// tabs, which is the point.
library;

/// Home's task selector; Profile's handle.
const double kHomeTitleTop = 102;

/// The selector's own padding, so a title that is not the selector still sits
/// on the same baseline.
const double kHomeTitlePadH = 8;
const double kHomeTitlePadV = 4;

/// The hero band: Home's dial, Profile's emblem.
const double kHomeDialTop = 152;
const double kHomeDialSize = 260;

/// Home's collective hint ("Pick a task to start a session"); Profile's
/// next-milestone line. The line is CENTRED inside a band of this height, so
/// both screens put the text on the same baseline rather than just the box.
const double kHomeSupportingTop = 448;
const double kHomeSupportingHeight = 56;

/// Home's "Last 10 days" heading; Profile's totals. The first full-width
/// block, and where each page's flowing content begins.
const double kHomeBlockTop = 511;

/// The gutter that block sits in.
const double kHomeGutter = 24;
