import CoreGraphics
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
      task("c", "Guitar", today: 900, total: 7_200, progress: 0.1),
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
      "medium-three", Self.medium,
      MediumWidgetView(entry: entry(three, selected: "b"))
    )
    shoot(
      "medium-five", Self.medium,
      MediumWidgetView(entry: entry(fiveTasks, selected: "b"))
    )
  }


  // MARK: - measuring what was drawn

  /// The medium widget's content box, in points: the page less the
  /// margin WidgetKit keeps, the dial, and the gap before the rows.
  static let contentTop: CGFloat = margin
  static let contentHeight: CGFloat = medium.height - margin * 2
  static let dialExtent: CGFloat = min(
    medium.height - margin * 2, (medium.width - margin * 2) * 0.42
  )
  static let rowsLeft: CGFloat = margin + dialExtent + 14
  static var contentCentre: CGFloat { contentTop + contentHeight / 2 }

  @MainActor
  private func image(_ content: some View, _ size: CGSize) -> CGImage? {
    let page = content
      .padding(Self.margin)
      .frame(width: size.width, height: size.height)
      .background(Ink.background)
    let renderer = ImageRenderer(content: page)
    renderer.scale = 3
    return renderer.cgImage
  }

  /// Top and bottom of everything drawn inside a band of columns, in
  /// points. Nothing but the background counts as nothing.
  private func ink(
    _ image: CGImage, from left: CGFloat, to right: CGFloat
  ) -> (top: CGFloat, bottom: CGFloat)? {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    guard
      let context = CGContext(
        data: &bytes, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    let scale = CGFloat(w) / Self.medium.width
    let x0 = max(0, Int(left * scale)), x1 = min(w, Int(right * scale))
    var top = -1, bottom = -1
    for y in 0 ..< h {
      var lit = false
      for x in x0 ..< x1 {
        let i = (y * w + x) * 4
        // The ground is #0A0A0A; anything brighter is drawn.
        if Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2]) > 0x3C {
          lit = true
          break
        }
      }
      if lit {
        if top < 0 { top = y }
        bottom = y
      }
    }
    guard top >= 0 else { return nil }
    return (CGFloat(top) / scale, CGFloat(bottom + 1) / scale)
  }

  /// The same rows, centred in the same column by SwiftUI itself
  /// rather than by the code under test.
  ///
  /// Comparing against this rather than against the middle of the box
  /// is what makes the measurement honest: a descender in the last name
  /// pushes the drawn ink lower than the row's layout box, and it does
  /// so identically in both renders, so the difference cancels.
  @MainActor
  private func centredControl(_ entry: TaskEntry) -> (top: CGFloat, bottom: CGFloat)? {
    let control = HStack(spacing: 14) {
      Color.clear.frame(width: Self.dialExtent, height: Self.dialExtent)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(entry.list) { task in
          MediumWidgetView.Row(entry: entry, task: task)
        }
      }
      .frame(
        width: Self.medium.width - Self.margin * 2 - Self.dialExtent - 14,
        height: Self.contentHeight,
        alignment: .leading
      )
    }
    guard let image = image(control, Self.medium) else { return nil }
    return ink(image, from: Self.rowsLeft, to: Self.medium.width)
  }

  /// The row block sits on the dial's centre line, for one row up to
  /// five: the space above the first row is the space below the last.
  @MainActor
  func testTheRowBlockIsCentredOnTheDial() {
    var measured: [String] = []
    for count in 1 ... 5 {
      let tasks = Array(fiveTasks.prefix(count))
      let e = entry(tasks, selected: tasks[0].id)
      guard
        let image = image(MediumWidgetView(entry: e), Self.medium),
        let rows = ink(image, from: Self.rowsLeft, to: Self.medium.width),
        let dial = ink(image, from: Self.margin, to: Self.margin + Self.dialExtent),
        let centred = centredControl(e)
      else { return XCTFail("nothing drawn for \(count) rows") }

      XCTAssertEqual(rows.top, centred.top, accuracy: 0.5, "\(count) rows, top")
      XCTAssertEqual(
        rows.bottom, centred.bottom, accuracy: 0.5, "\(count) rows, bottom"
      )
      // And what the owner sees: the same space above the block as
      // below it, measured against the dial's own edges.
      let above = rows.top - dial.top
      let below = dial.bottom - rows.bottom
      measured.append(
        "\(count) row(s): above \(round(above * 100) / 100)pt, "
          + "below \(round(below * 100) / 100)pt"
      )
    }
    // Left for the owner next to the shots, since a test's own output
    // never reaches the terminal that ran it.
    //
    // These are ink, not layout: a descender in the last name ("Spanish",
    // "Reading") draws about 2pt below its row, so the gap under the
    // block reads smaller even though the block is centred. Centring on
    // ink instead would move the whole list whenever a task was renamed,
    // so the rows are centred on their text boxes — which is what the
    // assertions above measure.
    measured.append(
      "(ink, not layout: a descender in the last name draws ~2pt lower)"
    )
    try? measured.joined(separator: "\n").write(
      to: Self.out.appendingPathComponent("centring.txt"),
      atomically: true, encoding: .utf8
    )
  }

  /// The dial itself is centred, which is what makes the line above the
  /// one the owner can see.
  @MainActor
  func testTheDialIsOnTheContentCentre() {
    let e = entry(threeTasks, selected: "a")
    guard
      let image = image(MediumWidgetView(entry: e), Self.medium),
      let dial = ink(image, from: Self.margin, to: Self.margin + Self.dialExtent)
    else { return XCTFail("no dial") }
    XCTAssertEqual(
      (dial.top + dial.bottom) / 2, Self.contentCentre, accuracy: 0.5
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
