import 'package:flutter/material.dart';
import '../../../shared/sondr_prompt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../shared/sondr_swipe_row.dart';
import '../../tasks/models/task.dart';
import '../../tasks/tasks_providers.dart';
import '../timer_controller.dart';

/// Sentinel returned by the dropdown when the user picks "Add Task".
const String _addTaskValue = '__add_task__';

/// Top-of-screen task switcher.
///
/// Tapping opens a minimal greyscale dropdown: a pinned "Select your task"
/// label, a list of slim full-width task pills, and a plain "Add Task" row at
/// the bottom. Each pill IS its own progress bar — a lighter-grey fill sweeps
/// left-to-right to show hours toward the first 20-hour milestone over a darker
/// remainder (the only place milestone progress is shown). The pill list is a
/// fixed area (~6 pills) that scrolls internally when there are more, so the
/// dropdown never grows unbounded.
///
/// All-tasks (collective) mode is reached by **double-tapping** the selector, so
/// it no longer needs a menu entry. The control is locked while a timer session
/// is active so logged time can't be misattributed by switching mid-session.
class TaskDropdown extends ConsumerStatefulWidget {
  const TaskDropdown({super.key});

  @override
  ConsumerState<TaskDropdown> createState() => _TaskDropdownState();
}

class _TaskDropdownState extends ConsumerState<TaskDropdown> {
  final GlobalKey _selectorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final selected = ref.watch(selectedTaskProvider);
    final locked = ref.watch(timerControllerProvider).isActive;
    final isCollective = selected == null;

    final label = isCollective ? 'Task' : selected.name;

    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked ? null : _openMenu,
        // Double-tap snaps back to the all-tasks overview; only meaningful when
        // a specific task is selected.
        onDoubleTap: (locked || isCollective) ? null : _snapToCollective,
        child: Container(
          key: _selectorKey,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // The phantom left box equals the chevron + gap, so the TEXT is what
          // optically centres on screen while the chevron hangs off its right.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 28),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down,
                  size: 22, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _snapToCollective() {
    ref.read(selectedTaskIdProvider.notifier).clear();
  }

  Future<void> _openMenu() async {
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      // Screen-global coordinates (no SafeArea) so the panel lands just beneath
      // the selector: 382x382 at X6. Top (146) sits just above the dial's top
      // (152) so the opaque panel fully covers the dial when open.
      useSafeArea: false,
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: _panelTop * figmaScale(context),
              left: 6 * figmaScale(context),
              child: const _TaskMenuPanel(),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;
    if (result == _addTaskValue) {
      await _promptAddTask();
    } else {
      ref.read(selectedTaskIdProvider.notifier).select(result);
    }
  }

  Future<void> _promptAddTask() async {
    final name = await showSondrPrompt(
      context,
      title: 'Add task',
      confirmLabel: 'Add',
    );
    if (!mounted || name == null) return;
    final task = await ref.read(tasksProvider.notifier).addTask(name);
    ref.read(selectedTaskIdProvider.notifier).select(task.id);
  }

}

/// Screen-global Y (reference space) the open panel is pinned at — just above
/// the dial's top (152) so the opaque panel covers it.
const double _panelTop = 146;

/// Panel metrics (Figma, 393-wide screen; container 382 wide at X6), with the
/// pills thickened from 20 to 28.
const double _panelWidth = 382;
const double _pillHeight = 28;
const int _maxVisiblePills = 6;

/// The one spacing unit: above the first pill, between pills, below the last
/// pill, and under the footer row. Even spacing throughout is what gives the
/// sheet its airy feel, so these are deliberately not tuned separately.
const double _panelSpacing = 21;

/// Height of the footer row — "Add Task" / "Archived", or "Back" (Inter 15).
const double _footerHeight = 18;

/// Height of the archived view's one-line empty state (13 regular).
const double _emptyLineHeight = 18;

/// Reference-space Y of Home's "Last 10 days" heading — the sheet must stay
/// above it so the heading and the day circles below it remain visible.
const double _lastTenDaysTop = 511;

/// Height of the pill list for [pills] visible pills.
double _listHeightFor(int pills) =>
    pills == 0 ? 0 : pills * _pillHeight + (pills - 1) * _panelSpacing;

/// Panel height around a pill list (or empty line) of [listHeight].
double _panelHeightFor(double listHeight) =>
    _panelSpacing + listHeight + _panelSpacing + _footerHeight + _panelSpacing;

/// The dropdown body: the task pills, then a footer row beneath them. One
/// spacing unit is used above the first pill, between the pills, below the
/// last one and under the footer, so the sheet reads as evenly spaced
/// throughout. It is only as tall as its contents — one task gives a compact
/// sheet — and grows per task up to [_maxVisiblePills], beyond which the pills
/// scroll. At its tallest it still stops above Home's "Last 10 days" heading
/// (asserted below). Pops the route with the chosen task id (or the add-task
/// sentinel).
///
/// Two lists, one sheet. The active list is the default: pills, "Add Task"
/// centred, and "Archive" hard right at the same weight and tone — two
/// actions of equal standing, told apart by position. "Archive" swaps the
/// SAME sheet over to the put-away tasks — same pills, same progress bars —
/// where the footer is a single grey "Back". The mode is local to the open
/// sheet, so closing the dropdown and reopening it always lands on the active
/// list.
class _TaskMenuPanel extends ConsumerStatefulWidget {
  const _TaskMenuPanel();

  @override
  ConsumerState<_TaskMenuPanel> createState() => _TaskMenuPanelState();
}

class _TaskMenuPanelState extends ConsumerState<_TaskMenuPanel> {
  bool _archived = false;

  /// Put [task] away, or bring it back.
  ///
  /// Clearing the selection matters: leaving the dial pointing at a task you
  /// have just archived would keep its name and its timer controls on Home —
  /// the ghost. Dropping the selection lands back on the collective "Task"
  /// overview, which is view-only.
  ///
  /// There is no running timer to orphan here. The selector is locked while a
  /// session is active (see [_TaskDropdownState.build]), so this sheet cannot
  /// be opened mid-session and a task cannot be archived out from under a
  /// running clock.
  Future<void> _setArchived(Task task, bool archived) async {
    if (archived && ref.read(selectedTaskIdProvider) == task.id) {
      ref.read(selectedTaskIdProvider.notifier).clear();
    }
    await ref.read(tasksProvider.notifier).setArchived(task.id, archived);
  }

  @override
  Widget build(BuildContext context) {
    // Guards the one hard constraint: even at its tallest the sheet may not
    // reach Home's "Last 10 days" heading.
    assert(
      _panelTop + _panelHeightFor(_listHeightFor(_maxVisiblePills)) <
          _lastTenDaysTop,
      'open task panel would cover the "Last 10 days" heading',
    );

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final selectedId = ref.watch(selectedTaskIdProvider);
    final tasks = _archived
        ? ref.watch(archivedTasksProvider)
        : ref.watch(activeTasksProvider);

    // Only the archived view says when it is empty. An empty ACTIVE list is a
    // first run, and "Add Task" directly beneath it is the whole answer.
    final showEmpty = _archived && tasks.isEmpty;
    final visiblePills = tasks.length.clamp(0, _maxVisiblePills);
    final listHeight = showEmpty
        ? _emptyLineHeight
        : _listHeightFor(visiblePills);
    final footerTop = _panelSpacing + listHeight + _panelSpacing;

    // "Add Task" is Inter Bold 15, white — the app's other headings. The
    // quiet ones take the supporting treatment, grey at regular weight.
    //
    // Built as bare Text rather than SondrAction deliberately: the footer's
    // height is a measured constant the panel's geometry depends on, and
    // SondrAction's 12 of vertical tap padding would make it 42 in an 18 row.
    final primaryStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );
    final quietStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15 * scale,
      fontWeight: FontWeight.w400,
      color: tokens.textSecondary,
    );

    // Horizontal padding only — it widens the tap target without changing the
    // row's height, which the panel is measured on.
    Widget footerAction(String label, TextStyle? style, VoidCallback onTap) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * scale),
            child: Text(label, style: style),
          ),
        );

    return SizedBox(
      width: _panelWidth * scale,
      height: _panelHeightFor(listHeight) * scale,
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(20 * scale),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Pills: 365 wide, centred (8.5 inset), one spacing unit down from
            // the top edge so the first pill is not flush against it.
            Positioned(
              left: 8.5 * scale,
              top: _panelSpacing * scale,
              width: 365 * scale,
              height: listHeight * scale,
              child: showEmpty
                  ? Center(
                      child: Text(
                        'No archived tasks.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13 * scale,
                          color: tokens.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: _panelSpacing * scale),
                      itemBuilder: (context, i) {
                        final task = tasks[i];
                        // The app's one swipe: left to reveal, tray on the
                        // right, exactly as Friends and the comments sheet do
                        // it. Reveal, never dismiss — the gesture uncovers the
                        // word and waits for a tap, and a tap anywhere on the
                        // open row closes it again.
                        return SondrSwipeRow(
                          actions: [
                            _PillTrayAction(
                              label: _archived ? 'Unarchive' : 'Archive',
                              onTap: () => _setArchived(task, !_archived),
                            ),
                          ],
                          child: _TaskPill(
                            scale: scale,
                            label: task.name,
                            progress: task.milestoneProgress,
                            started: task.totalSeconds >= 60,
                            selected: task.id == selectedId,
                            // An archived pill is a record, not a choice —
                            // tapping it must not put you back on it. Bring it
                            // back with Unarchive first.
                            onTap: _archived
                                ? null
                                : () => Navigator.of(context).pop(task.id),
                          ),
                        );
                      },
                    ),
            ),
            // The footer row, one spacing unit below the last pill and the
            // same again above the panel's bottom edge.
            Positioned(
              left: 0,
              right: 0,
              top: footerTop * scale,
              child: _archived
                  // "Back" already reverses the "Archived" that got here, so
                  // this view carries no second toggle.
                  ? Center(
                      child: footerAction(
                        'Back',
                        quietStyle,
                        () => setState(() => _archived = false),
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        footerAction(
                          'Add Task',
                          primaryStyle,
                          () => Navigator.of(context).pop(_addTaskValue),
                        ),
                        // Same row, same baseline, hard right — and the
                        // same type as "Add Task" beside it. Two actions of
                        // equal standing, told apart by position alone, which
                        // is where hierarchy is supposed to come from.
                        Positioned(
                          right: 2 * scale,
                          child: footerAction(
                            'Archive',
                            primaryStyle,
                            () => setState(() => _archived = true),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A swipe-tray action sized for a 28-tall pill.
///
/// [SondrAction] cannot go in here: its 12 of vertical tap padding makes it
/// around 40 tall, and a 28 pill row has no room for that — it would break the
/// panel's measured height. So the label is built at the PILL's own type
/// (12/bold/textPrimary) with horizontal padding for the tap target.
///
/// White at full emphasis, like every other tray action: it was summoned by a
/// deliberate gesture rather than standing on the screen, so it costs nothing
/// in clutter and has nothing to be de-emphasised against (DESIGN.md).
class _PillTrayAction extends StatelessWidget {
  const _PillTrayAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// A 28-tall task pill (fully rounded) that doubles as its own progress bar: a
/// lighter-grey fill sweeps from the left over a darker remainder, in proportion
/// to [progress] (0..1) through the current 20-hour block — the same measure
/// the profile rings use, so a filled bar means the same thing everywhere.
/// Empty = all dark, complete = all light; it resets on each milestone and
/// climbs again toward the next. Once [started] (a minute or more logged) the fill is
/// never narrower than a thin sliver, so a little time never reads as
/// none. The filled left end is rounded by the pill; the
/// filled/unfilled boundary is a clean vertical edge. Name centred, Inter bold
/// 12, white. Pure greyscale — fill and remainder are a brightness step apart.
class _TaskPill extends StatelessWidget {
  const _TaskPill({
    required this.scale,
    required this.label,
    required this.progress,
    required this.started,
    required this.selected,
    required this.onTap,
  });

  static const double _height = 28;

  /// Narrowest fill once [started]: a thin sliver of the rounded left end.
  static const double _minFill = 8;

  /// Figma-reference scale, so pills grow with the panel around them.
  final double scale;

  final String label;
  final double progress;
  final bool started;
  final bool selected;

  /// Null on an archived row — a record, not a choice.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final height = _height * scale;
    final remainder = Color.lerp(tokens.surface, tokens.ringTrack, 0.5)!;
    final fill = Color.lerp(tokens.ringTrack, tokens.ringFillInner, 0.35)!;
    final nameStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: remainder),
              if (started || progress > 0)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final full = constraints.maxWidth;
                    var width = full * progress.clamp(0.0, 1.0);
                    final minFill = _minFill * scale;
                    if (started && width < minFill) width = minFill;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: ColoredBox(color: fill),
                      ),
                    );
                  },
                ),
              // Subtle selected outline; drawn inside the clip so it never
              // changes the pill's exact 28px height. (Not in the measured
              // spec — kept minimal; easy to drop.)
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height / 2),
                    border:
                        Border.all(color: tokens.ringFillInner, width: 1.5),
                  ),
                ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: nameStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
