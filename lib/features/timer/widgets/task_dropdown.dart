import 'package:flutter/material.dart';
import '../../../shared/sondr_prompt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/figma_scale.dart';
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
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    final selectedId = ref.read(selectedTaskIdProvider);

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
              child: _TaskMenuPanel(tasks: tasks, selectedId: selectedId),
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

/// The dropdown body: the task pills, then a plain "Add Task" row beneath
/// them. One spacing unit is used above the first pill, between the pills,
/// below the last one and under "Add Task", so the sheet reads as evenly
/// spaced throughout. It is only as tall as its contents — one task gives a
/// compact sheet — and grows per task up to [_maxVisiblePills], beyond which
/// the pills scroll. At its tallest it still stops above Home's "Last 10 days"
/// heading (asserted below). Pops the route with the chosen task id (or the
/// add-task sentinel).
class _TaskMenuPanel extends StatelessWidget {
  const _TaskMenuPanel({required this.tasks, required this.selectedId});

  final List<Task> tasks;
  final String? selectedId;

  // Figma metrics (393-wide screen; container 382 wide at X6), with pills
  // thickened from 20 to 28.
  static const double _containerWidth = 382;
  static const double _pillHeight = 28;
  static const int _maxVisiblePills = 6;

  /// The one spacing unit: above the first pill, between pills, below the last
  /// pill, and under "Add Task". Even spacing throughout is what gives the
  /// sheet its airy feel, so these are deliberately not tuned separately.
  static const double _spacing = 21;

  /// Height of the "Add Task" row (Inter Bold 15).
  static const double _addTaskHeight = 18;

  /// Reference-space Y of Home's "Last 10 days" heading — the sheet must stay
  /// above it so the heading and the day circles below it remain visible.
  static const double _lastTenDaysTop = 511;

  /// Panel height for [pills] visible pills, contents evenly spaced.
  static double _heightFor(int pills) {
    final list = pills == 0
        ? 0.0
        : pills * _pillHeight + (pills - 1) * _spacing;
    return _spacing + list + _spacing + _addTaskHeight + _spacing;
  }

  @override
  Widget build(BuildContext context) {
    // Guards the one hard constraint: even at its tallest the sheet may not
    // reach Home's "Last 10 days" heading.
    assert(
      _panelTop + _heightFor(_maxVisiblePills) < _lastTenDaysTop,
      'open task panel would cover the "Last 10 days" heading',
    );

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    // "Add Task" is Inter Bold 15, white (textPrimary), matching the app's
    // other headings. Pill names keep their own style.
    final addTaskStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );

    final visiblePills = tasks.length.clamp(0, _maxVisiblePills);
    final listHeight = visiblePills == 0
        ? 0.0
        : visiblePills * _pillHeight + (visiblePills - 1) * _spacing;
    final addTaskTop = _spacing + listHeight + _spacing;
    final containerHeight = _heightFor(visiblePills);

    return SizedBox(
      width: _containerWidth * scale,
      height: containerHeight * scale,
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
              top: _spacing * scale,
              width: 365 * scale,
              height: listHeight * scale,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: tasks.length,
                separatorBuilder: (_, _) => SizedBox(height: _spacing * scale),
                itemBuilder: (context, i) {
                  final task = tasks[i];
                  return _TaskPill(
                    scale: scale,
                    label: task.name,
                    progress: task.milestoneProgress,
                    started: task.totalSeconds >= 60,
                    selected: task.id == selectedId,
                    onTap: () => Navigator.of(context).pop(task.id),
                  );
                },
              ),
            ),
            // "Add Task", one spacing unit below the last pill and the same
            // again above the panel's bottom edge.
            Positioned(
              left: 0,
              right: 0,
              top: addTaskTop * scale,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(_addTaskValue),
                child: Center(child: Text('Add Task', style: addTaskStyle)),
              ),
            ),
          ],
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
  final VoidCallback onTap;

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
