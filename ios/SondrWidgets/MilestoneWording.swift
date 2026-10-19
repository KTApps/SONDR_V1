import Foundation

/// How long is left of the current twenty hours, in words.
///
/// A running card hands the remaining time to the system as a date, because
/// that is the only countdown that keeps moving without the app being woken
/// to retype it — and the system then picks the wording. A paused card has
/// to write the line itself, and has to write it the same way: pausing must
/// stop the clock, not reword the sentence under it.
///
/// Hours and minutes, abbreviated and comma-separated, in the viewer's
/// locale — the formatter the system's own countdown is built on.
enum MilestoneWording {
  private static let formatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .short
    // An hour exactly comes out "1 hr", and forty-five minutes "45 min":
    // the default behaviour already drops the zero unit at either end, so
    // zeroFormattingBehavior is left alone. Two tests hold that.
    formatter.maximumUnitCount = 2
    return formatter
  }()

  /// "3 hrs, 8 min", "1 hr", "45 min", "1 min".
  static func remaining(_ seconds: TimeInterval) -> String {
    // Nothing is "0 min", and a milestone a few seconds away is not zero
    // minutes away — it is a minute away.
    formatter.string(from: max(60, seconds.rounded())) ?? ""
  }
}
