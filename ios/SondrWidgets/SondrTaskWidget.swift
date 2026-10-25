import AppIntents
import SwiftUI
import WidgetKit

/// The Home Screen widget: what you are tracking, and one tap to start.
///
/// Two families. Small is one task — its milestone ring, today's time,
/// and Start — with dots for the rest of the widget's list. Medium is
/// Home's own dial beside the list, so the whole day reads at a glance.
@available(iOS 17.0, *)
struct SondrTaskWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "SondrTaskWidget",
      intent: TasksConfiguration.self,
      provider: TaskTimelineProvider()
    ) { entry in
      TaskWidgetView(entry: entry)
        .containerBackground(Ink.background, for: .widget)
    }
    .configurationDisplayName("Tasks")
    .description("Today's time, and one tap to start.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

/// One moment, as the widget draws it.
@available(iOS 17.0, *)
struct TaskEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot
  let list: [WidgetTask]
  let session: SessionSnapshot?

  /// The task this widget is showing.
  ///
  /// A session outranks the selection: while one is on, the task being
  /// tracked is the task on screen, and nothing on the widget changes
  /// that until it ends.
  var current: WidgetTask? {
    if let id = session?.taskId, let running = list.first(where: { $0.id == id }) {
      return running
    }
    return list.first { $0.id == snapshot.selectedTaskId } ?? list.first
  }

  /// Whether there is a session at all. Stop and Pause belong to the
  /// session rather than to the task on screen, so this — not
  /// `runningHere` — is what decides whether they are offered.
  var hasSession: Bool { session != nil }

  var isPaused: Bool { session?.isPaused ?? false }

  var isRunning: Bool { session != nil }

  /// Whether the running session belongs to the task on screen.
  var runningHere: Bool {
    guard let session, let current else { return false }
    return session.taskId == current.id
  }
}

@available(iOS 17.0, *)
struct TaskTimelineProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> TaskEntry {
    TaskEntry(date: Date(), snapshot: WidgetSnapshot(), list: [], session: nil)
  }

  func snapshot(
    for configuration: TasksConfiguration,
    in context: Context
  ) async -> TaskEntry {
    entry(for: configuration)
  }

  func timeline(
    for configuration: TasksConfiguration,
    in context: Context
  ) async -> Timeline<TaskEntry> {
    // One entry, held until the app says otherwise. A running clock
    // advances on the device through Text(timerInterval:), so there is
    // nothing to schedule — the same reason the Live Activity has no
    // staleDate.
    Timeline(entries: [entry(for: configuration)], policy: .never)
  }

  private func entry(for configuration: TasksConfiguration) -> TaskEntry {
    let snapshot = WidgetSnapshot.read() ?? WidgetSnapshot()
    let ids = configuration.chosenIds
    let list = ids.isEmpty
      ? WidgetList.automatic(snapshot.tasks)
      : WidgetList.chosen(ids, from: snapshot)
    let session = SessionBox.read(from: SessionBox.sharedDefaults)
      .flatMap(SessionSnapshot.from)
    return TaskEntry(
      date: Date(),
      snapshot: snapshot,
      list: list,
      session: session
    )
  }
}

@available(iOS 17.0, *)
struct TaskWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TaskEntry

  var body: some View {
    if entry.list.isEmpty {
      EmptyWidgetView()
    } else if family == .systemMedium {
      MediumWidgetView(entry: entry)
    } else {
      SmallWidgetView(entry: entry)
    }
  }
}

/// Nothing to show: no tasks, or a guest who has not made one.
@available(iOS 17.0, *)
struct EmptyWidgetView: View {
  var body: some View {
    // A widgetURL rather than an intent: there is nothing to do here but
    // go and make a task.
    VStack {
      Spacer()
      Text("Add a task in sondr")
        .font(.inter(13, .regular))
        .foregroundStyle(Ink.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .widgetURL(SondrLink.home)
  }
}

/// One task: the ring, the name, today, and the action.
@available(iOS 17.0, *)
struct SmallWidgetView: View {
  let entry: TaskEntry

  private var task: WidgetTask? { entry.current }

  var body: some View {
    GeometryReader { geo in
      let ring = min(geo.size.width, geo.size.height) * 0.52
      VStack(alignment: .leading, spacing: 0) {
        // Stop is the session's control, not the task's: top right,
        // level with the top of the ring, and only there while there is
        // a session to stop.
        HStack(alignment: .top) {
          MilestoneRing(
            progress: task?.progress ?? 0,
            complete: task?.isMilestoneComplete ?? false,
            diameter: ring
          )
          Spacer()
          if entry.hasSession { StopAction(size: 14) }
        }
        Spacer(minLength: 8)
        name
        Spacer(minLength: 2)
        // The primary keeps one place whatever it says.
        HStack(alignment: .firstTextBaseline) {
          today
          Spacer(minLength: 4)
          PrimaryAction(entry: entry, task: task, size: 14)
        }
        if entry.list.count > 1 {
          Spacer(minLength: 6)
          Dots(count: entry.list.count, current: index)
        }
      }
    }
  }

  private var index: Int {
    entry.list.firstIndex { $0.id == task?.id } ?? 0
  }

  /// Tapping the name moves to the next task in this widget's list — and
  /// tells the app, so the two always agree about what is selected. A
  /// list of one has nowhere to go, so it opens the app instead.
  ///
  /// While a session is on it is not a control at all: the task being
  /// tracked is the task shown, until it ends.
  @ViewBuilder private var name: some View {
    let label = Text(task?.name ?? "")
      .font(.inter(13, .semibold))
      .foregroundStyle(Ink.secondary)
      .lineLimit(1)
    if entry.hasSession {
      label
    } else if entry.list.count > 1 {
      Button(
        intent: CycleTaskIntent(
          ids: entry.list.map(\.id),
          current: task?.id ?? ""
        )
      ) { label }
        .buttonStyle(.plain)
    } else {
      Link(destination: SondrLink.home) { label }
    }
  }

  private var today: some View {
    Group {
      if entry.runningHere, let session = entry.session {
        RunningTime(session: session, size: 20)
      } else {
        Text(Clock.hm(task?.today ?? 0))
          .font(.inter(20, .bold))
          .monospacedDigit()
          .foregroundStyle(Ink.primary)
          .invalidatableContent()
      }
    }
  }

}

/// Home's dial, and the list beside it.
@available(iOS 17.0, *)
struct MediumWidgetView: View {
  let entry: TaskEntry

  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 14) {
        let dial = min(geo.size.height, geo.size.width * 0.42)
        DayDial(entry: entry, extent: dial)
          .frame(width: dial, height: dial)
        // Centred on the dial, not hung from the top: one task sits
        // level with the dial's centre and more rows grow outward from
        // there, so the space above the first and below the last is the
        // same. The dial is centred by the HStack, so both blocks share
        // the one centre line.
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(entry.list.enumerated()), id: \.element.id) { _, task in
            Row(entry: entry, task: task)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
    }
  }

  /// One task. Its name, and either its time or — when it is the
  /// selected one — the action.
  @available(iOS 17.0, *)
  struct Row: View {
    let entry: TaskEntry
    let task: WidgetTask

    private var isSelected: Bool { task.id == entry.current?.id }

    @ViewBuilder var body: some View {
      let line = HStack(spacing: 6) {
        Text(task.name)
          .font(.inter(13, .semibold))
          .foregroundStyle(isSelected ? Ink.primary : Ink.tertiary)
          .lineLimit(1)
        Spacer(minLength: 4)
        if isSelected {
          // Stop first, the primary last: the right-hand control is
          // always the one that gets the session going.
          HStack(spacing: 14) {
            if entry.hasSession { StopAction(size: 13) }
            PrimaryAction(entry: entry, task: task, size: 13)
          }
        } else {
          Text(Clock.hm(task.today))
            .font(.inter(12, .regular))
            .monospacedDigit()
            .foregroundStyle(Ink.tertiary)
        }
      }
      .padding(.vertical, 3)

      // A row chooses a task, and nothing chooses while a session is on.
      if entry.hasSession {
        line
      } else {
        Button(intent: SelectTaskIntent(id: task.id)) { line }
          .buttonStyle(.plain)
      }
    }
  }
}

/// The primary: Start, Pause, or Start again after a pause.
///
/// One word in one place. It belongs to the session when there is one —
/// pausing and going again are the session's business, and both run in
/// place through the intents the Lock Screen card already uses, so the
/// app is never opened for them.
@available(iOS 17.0, *)
struct PrimaryAction: View {
  let entry: TaskEntry
  let task: WidgetTask?
  let size: CGFloat

  @ViewBuilder var body: some View {
    if entry.hasSession {
      if entry.isPaused {
        // It says "Start", because that is the word for going again.
        // VoiceOver hears "Resume", because that is what it does.
        Button(intent: ResumeSessionIntent()) {
          word(PrimaryWord.label(hasSession: true, isPaused: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PrimaryWord.resumeSpoken)
      } else {
        Button(intent: PauseSessionIntent()) {
          word(PrimaryWord.label(hasSession: true, isPaused: false))
        }
        .buttonStyle(.plain)
      }
    } else if let task {
      Button(intent: StartSessionIntent(id: task.id)) {
        word(PrimaryWord.label(hasSession: false, isPaused: false))
      }
      .buttonStyle(.plain)
    }
  }

  private func word(_ text: String) -> some View {
    Text(text)
      .font(.inter(size, .bold))
      .foregroundStyle(Ink.primary)
      .invalidatableContent()
  }
}

/// Stop — only while there is a session, and quieter than the primary:
/// the grey and weight the Lock Screen card gives it.
///
/// Stopping is the end of a session: the camera, the milestone, the
/// post. That belongs in the app, so this asks the app to do it:
/// `StopSessionIntent` leaves a flag and opens the app, and the app acts
/// on the flag the moment it is active. Not a Link — a widget styles a
/// Link its own way — and not OpenURLIntent, which cannot open a custom
/// scheme and so did nothing.
@available(iOS 17.0, *)
struct StopAction: View {
  let size: CGFloat

  var body: some View {
    Button(intent: StopSessionIntent()) {
      Text("Stop")
        .font(.inter(size, .regular))
        .foregroundStyle(Ink.secondary)
        .invalidatableContent()
    }
    .buttonStyle(.plain)
  }
}

/// A clock that advances on the device, with nothing pushed to it.
@available(iOS 17.0, *)
struct RunningTime: View {
  let session: SessionSnapshot
  let size: CGFloat

  var body: some View {
    Group {
      if session.isPaused {
        Text(Clock.hm(Int(session.elapsed(at: Date()))))
      } else {
        Text(
          Date(timeIntervalSinceNow: -session.elapsed(at: Date())),
          style: .timer
        )
      }
    }
    .font(.inter(size, .bold))
    .monospacedDigit()
    .foregroundStyle(session.isPaused ? Ink.tertiary : Ink.primary)
    // Greyed from the tap until the next timeline lands, so a tap that
    // takes a moment reads as taken, not ignored.
    .invalidatableContent()
  }
}

/// The milestone ring, thin — the in-progress weight the Profile's tiles
/// use: a 3pt stroke on a 56pt tile, kept as a ratio so it is the same
/// ring at any size.
@available(iOS 17.0, *)
struct MilestoneRing: View {
  let progress: Double
  let complete: Bool
  let diameter: CGFloat

  static let strokeRatio: CGFloat = 3.0 / 56.0

  private var stroke: CGFloat { diameter * Self.strokeRatio }

  var body: some View {
    ZStack {
      Circle()
        .inset(by: stroke / 2)
        .stroke(Ink.ringTrack, lineWidth: stroke)
      Circle()
        .inset(by: stroke / 2)
        .trim(from: 0, to: max(0, min(1, progress)))
        .stroke(
          complete ? Ink.ringComplete : Ink.ringFill,
          style: StrokeStyle(lineWidth: stroke, lineCap: .butt)
        )
        .rotationEffect(.degrees(-90))
    }
    .frame(width: diameter, height: diameter)
  }
}

/// Which task of the widget's list is showing.
@available(iOS 17.0, *)
struct Dots: View {
  let count: Int
  let current: Int

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0 ..< count, id: \.self) { i in
        Circle()
          .fill(i == current ? Ink.ringFill : Ink.ringTrack)
          .frame(width: 4, height: 4)
      }
    }
  }
}

/// Home's dial, scaled down.
///
/// The same proportions the app's own dial uses — outer 290, inner 220,
/// stroke 22 and a 5pt slit on a 312 extent — so this is that dial, not
/// a drawing of one. The outer band is today's time split by task with
/// the selected slice bright; the inner is one segment per habit.
@available(iOS 17.0, *)
struct DayDial: View {
  let entry: TaskEntry
  let extent: CGFloat

  static let outerRatio: CGFloat = 290.0 / 312.0
  static let innerRatio: CGFloat = 220.0 / 312.0
  static let strokeRatio: CGFloat = 22.0 / 312.0
  static let slitRatio: CGFloat = 5.0 / 312.0

  private var stroke: CGFloat { extent * Self.strokeRatio }

  var body: some View {
    ZStack {
      band(
        diameter: extent * Self.outerRatio,
        segments: slices,
        selected: selectedSlice
      )
      // The habit band never turns, as on Home.
      band(
        diameter: extent * Self.innerRatio,
        segments: innerSegments
      )
      centre
    }
    .frame(width: extent, height: extent)
  }

  /// Today's split, with the selected task bright. No time at all is one
  /// empty ring rather than a ring of nothing.
  ///
  /// Only tasks with time today get a slice, as on Home.
  private var slices: [(weight: Double, colour: Color)] {
    DialBand.entries(entry.snapshot).map { item in
      let task = entry.snapshot.tasks[item.index]
      return (
        Double(item.seconds),
        task.id == entry.current?.id ? Ink.primary : Ink.ringFill
      )
    }
  }

  /// Which slice the selected task has, if it has one.
  private var selectedSlice: Int? {
    DialBand.entries(entry.snapshot).firstIndex {
      entry.snapshot.tasks[$0.index].id == entry.current?.id
    }
  }

  private var innerSegments: [(weight: Double, colour: Color)] {
    let total = entry.snapshot.habitsTotal
    guard total > 0 else { return [(1, Ink.ringTrack)] }
    return (0 ..< total).map { i in
      (1, i < entry.snapshot.habitsDone ? Ink.ringFill : Ink.ringTrack)
    }
  }

  /// One band. The slices are laid out by Home's rule and then turned so
  /// the selected one opens at 12; a slice pushed past the top is drawn
  /// in two pieces, because a trim cannot wrap.
  private func band(
    diameter: CGFloat,
    segments: [(weight: Double, colour: Color)],
    selected: Int? = nil
  ) -> some View {
    let slices = segments.isEmpty ? [(weight: 1.0, colour: Ink.ringTrack)] : segments
    // A slit is a fixed length of band, so how much of a turn it takes
    // depends on the radius.
    let slit = slices.count > 1
      ? Double(extent * Self.slitRatio / (.pi * diameter))
      : 0
    let weights = slices.map(\.weight)
    let starts = DialBand.starts(weights: weights, slit: slit)
    let sweeps = DialBand.sweeps(weights: weights, slit: slit)
    let turn = DialBand.rotation(starts: starts, selected: selected)

    var arcs: [(Double, Double, Color)] = []
    for (i, slice) in slices.enumerated() {
      let from = (starts[i] + slit / 2 - turn).truncatingRemainder(dividingBy: 1)
      let begin = from < 0 ? from + 1 : from
      let end = begin + sweeps[i]
      if end <= 1 {
        arcs.append((begin, end, slice.colour))
      } else {
        arcs.append((begin, 1, slice.colour))
        arcs.append((0, end - 1, slice.colour))
      }
    }

    return ZStack {
      ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
        Circle()
          .inset(by: stroke / 2)
          .trim(from: arc.0, to: arc.1)
          .stroke(arc.2, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
          .rotationEffect(.degrees(-90))
      }
    }
    .frame(width: diameter, height: diameter)
  }

  /// What Home shows in the middle when a task is selected: its time
  /// today, and the word for what that is.
  ///
  /// Fixed width and centred, because `Text(timerInterval:)` reserves
  /// room for the widest reading it could ever show and draws the
  /// digits at the leading edge of that. Left to itself the ticking
  /// clock sits off centre and runs into the ring.
  private var centre: some View {
    VStack(spacing: 0) {
      if entry.runningHere, let session = entry.session {
        RunningTime(session: session, size: 17)
      } else {
        Text(Clock.hm(entry.current?.today ?? 0))
          .font(.inter(17, .bold))
          .monospacedDigit()
          .foregroundStyle(Ink.primary)
      }
      Text("today")
        .font(.inter(10, .semibold))
        .foregroundStyle(Ink.secondary)
    }
    .frame(width: extent * Self.innerRatio - stroke * 2)
    .multilineTextAlignment(.center)
    .invalidatableContent()
  }
}

/// Seconds as the app writes them: "1h 20m", "45m".
enum Clock {
  static func hm(_ seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours == 0 { return "\(minutes)m" }
    if minutes == 0 { return "\(hours)h" }
    return "\(hours)h \(minutes)m"
  }
}
