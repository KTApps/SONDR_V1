import Foundation

/// One piece of work at one future instant, replaceable and cancellable.
///
/// A sleeping task and nothing more. It runs only if the process is still
/// awake when the instant arrives, which is the whole of its contract: the
/// caller has already accepted that a suspended app does not fire it.
final class ScheduledUpdate {
  private var task: Task<Void, Never>?

  /// Replace whatever was booked with `action` at `date`. A date already
  /// passed runs it at once.
  func schedule(
    at date: Date,
    now: Date = Date(),
    _ action: @escaping @Sendable () async -> Void
  ) {
    cancel()
    let delay = max(0, date.timeIntervalSince(now))
    task = Task {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await action()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  var isScheduled: Bool {
    guard let task else { return false }
    return !task.isCancelled
  }
}
