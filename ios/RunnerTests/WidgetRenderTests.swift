import CoreText
import SwiftUI
import UIKit
import WidgetKit
import XCTest

/// Renders every state of the Home Screen widget to a PNG, at the true
/// size the system gives it.
///
/// Not an assertion — a photograph. A widget cannot be looked at from a
/// test run, and the only way to judge one before it is on a Home Screen
/// is to render the view at its real size and open the file.
///
/// The views are rendered directly rather than through `TaskWidgetView`:
/// `\.widgetFamily` is a read-only environment value, so the family
/// cannot be imposed from outside the system. Picking the view by hand is
/// the same choice `TaskWidgetView` makes.
@available(iOS 17.0, *)
final class WidgetRenderTests: XCTestCase {
  /// Where the files go. Read back by whatever ran this.
  static let out = URL(fileURLWithPath: "/tmp/sondr-widget-shots")

  /// What WidgetKit hands a widget on a 393pt screen, in points, and the
  /// margin it keeps around the content.
  static let small = CGSize(width: 170, height: 170)
  static let medium = CGSize(width: 364, height: 170)
  static let margin: CGFloat = 16

  override class func setUp() {
    try? FileManager.default.removeItem(at: out)
    try? FileManager.default.createDirectory(
      at: out, withIntermediateDirectories: true
    )
    registerInter()
  }

  /// The widget extension bundles Inter; a test target does not, and
  /// `Font.custom` falls back to the system face without saying so — the
  /// shots would then be of a typeface the widget never uses. Register
  /// the repository's own file, found from this source file's path.
  private static func registerInter() {
    let font = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // RunnerTests
      .deletingLastPathComponent()  // ios
      .deletingLastPathComponent()  // the repository
      .appendingPathComponent("assets/fonts/Inter-Variable.ttf")
    CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
  }

  private func task(
    _ id: String,
    _ name: String,
    today: Int = 0,
    total: Int = 0,
    progress: Double = 0
  ) -> WidgetTask {
    WidgetTask(
      id: id, name: name, today: today, total: total,
      progress: progress, lastTracked: "2026-10-24"
    )
  }

  private var threeTasks: [WidgetTask] {
    [
      task("a", "Golf", today: 5_400, total: 61_200, progress: 0.85),
      task("b", "Spanish", today: 1_500, total: 18_000, progress: 0.25),
      task("c", "Guitar", today: 0, total: 7_200, progress: 0.1),
    ]
  }

  private func entry(
    _ tasks: [WidgetTask],
    selected: String,
    session: SessionSnapshot? = nil
  ) -> TaskEntry {
    TaskEntry(
      date: Date(),
      snapshot: WidgetSnapshot(
        tasks: tasks,
        segments: tasks.map(\.today),
        habitsDone: 2,
        habitsTotal: 3,
        selectedTaskId: selected
      ),
      list: tasks,
      session: session
    )
  }

  @MainActor
  private func shoot(_ name: String, _ size: CGSize, _ content: some View) {
    let page = content
      .padding(Self.margin)
      .frame(width: size.width, height: size.height)
      .background(Ink.background)
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: page)
    renderer.scale = 3
    guard let image = renderer.uiImage, let png = image.pngData() else {
      return XCTFail("nothing rendered for \(name)")
    }
    let file = Self.out.appendingPathComponent("\(name).png")
    XCTAssertNoThrow(try png.write(to: file), name)
    print("SHOT \(file.path) \(Int(size.width))x\(Int(size.height))pt")
  }

  /// Guards the other two: a shot in the wrong typeface is not proof.
  func testTheWidgetsOwnTypefaceIsLoaded() {
    XCTAssertNotNil(UIFont(name: "Inter", size: 13))
  }

  // MARK: - small

  @MainActor
  func testSmallStates() {
    let three = threeTasks
    shoot("small-idle", Self.small, SmallWidgetView(entry: entry(three, selected: "a")))
    shoot(
      "small-running", Self.small,
      SmallWidgetView(entry: entry(three, selected: "a", session: running))
    )
    shoot(
      "small-paused", Self.small,
      SmallWidgetView(entry: entry(three, selected: "a", session: paused))
    )
    shoot(
      "small-one-task", Self.small,
      SmallWidgetView(entry: entry([three[0]], selected: "a"))
    )
    shoot("small-empty", Self.small, EmptyWidgetView())
  }

  // MARK: - medium

  @MainActor
  func testMediumStates() {
    let three = threeTasks
    shoot("medium-idle", Self.medium, MediumWidgetView(entry: entry(three, selected: "a")))
    shoot(
      "medium-running", Self.medium,
      MediumWidgetView(entry: entry(three, selected: "a", session: running))
    )
    shoot(
      "medium-paused", Self.medium,
      MediumWidgetView(entry: entry(three, selected: "a", session: paused))
    )
    shoot(
      "medium-one-task", Self.medium,
      MediumWidgetView(entry: entry([three[0]], selected: "a"))
    )
    shoot("medium-empty", Self.medium, EmptyWidgetView())
    shoot(
      "medium-five", Self.medium,
      MediumWidgetView(entry: entry(fiveTasks, selected: "b"))
    )
  }

  // MARK: - fixtures

  private var fiveTasks: [WidgetTask] {
    threeTasks + [
      task("d", "Reading", today: 600, total: 3_600, progress: 0.05),
      task("e", "Running", today: 2_400, total: 144_000, progress: 1),
    ]
  }

  private var running: SessionSnapshot {
    SessionSnapshot(
      startedAt: Date(timeIntervalSinceNow: -1_500),
      taskId: "a",
      taskName: "Golf",
      taskSecondsBefore: 61_200
    )
  }

  private var paused: SessionSnapshot {
    SessionSnapshot(
      startedAt: Date(timeIntervalSinceNow: -1_500),
      pausedTotal: 120,
      pausedAt: Date(timeIntervalSinceNow: -60),
      taskId: "a",
      taskName: "Golf",
      taskSecondsBefore: 61_200
    )
  }
}
