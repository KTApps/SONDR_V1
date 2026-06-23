import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
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
      // the selector: 382x355 at X6. Top (146) sits just above the dial's top
      // (152) so the opaque panel fully covers the dial when open.
      useSafeArea: false,
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: 146,
              left: 6,
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
    final controller = TextEditingController();
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    // Same capsule base as the task pills, so the field matches their language.
    final fieldBase = Color.lerp(tokens.surface, tokens.ringTrack, 0.5)!;

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add task'),
          content: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: fieldBase,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: controller,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: tokens.textPrimary,
              ),
              cursorColor: tokens.textPrimary,
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                hintText: 'e.g. Spanish',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: tokens.textTertiary,
                ),
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: tokens.textSecondary,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.ringFillOuter,
                foregroundColor: tokens.background,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: const StadiumBorder(),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final task = await ref.read(tasksProvider.notifier).addTask(trimmed);
    ref.read(selectedTaskIdProvider.notifier).select(task.id);
  }
}

/// The dropdown body: pinned label, a fixed-height scrolling pill list, and a
/// pinned plain "Add Task" row. Pops the route with the chosen task id (or the
/// add-task sentinel).
class _TaskMenuPanel extends StatelessWidget {
  const _TaskMenuPanel({required this.tasks, required this.selectedId});

  final List<Task> tasks;
  final String? selectedId;

  // Exact Figma metrics (393-wide screen; container is 382x355 at X6/Y169).
  static const double _containerWidth = 382;
  static const double _containerHeight = 355;
  static const double _pillHeight = 20;
  static const double _pillGap = 25;
  static const int _maxVisiblePills = 6;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    // "Select your task", pill names, and "Add Task" are all Inter Bold 12.
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: tokens.textSecondary,
    );

    // The scrolling pill viewport: exactly six pills tall; more than six scroll.
    const viewport =
        _maxVisiblePills * _pillHeight + (_maxVisiblePills - 1) * _pillGap;

    return SizedBox(
      width: _containerWidth,
      height: _containerHeight,
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // "Select your task" at X15, Y176 (container-relative 9, 7).
            Positioned(
              left: 9,
              top: 7,
              child: Text('Select your task', style: labelStyle),
            ),
            // Pills: 365 wide, centred (8.5 inset); first top at Y201 (offset 32).
            Positioned(
              left: 8.5,
              top: 32,
              width: 365,
              height: viewport,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: _pillGap),
                itemBuilder: (context, i) {
                  final task = tasks[i];
                  return _TaskPill(
                    label: task.name,
                    progress: task.firstMilestoneProgress,
                    selected: task.id == selectedId,
                    onTap: () => Navigator.of(context).pop(task.id),
                  );
                },
              ),
            ),
            // "Add Task" centred at Y483 (container-relative 314).
            Positioned(
              left: 0,
              right: 0,
              top: 314,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(_addTaskValue),
                child: Center(child: Text('Add Task', style: labelStyle)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim 335×20 task pill (radius 10) that doubles as its own progress bar: a
/// lighter-grey fill sweeps from the left over a darker remainder, in proportion
/// to [progress] (0..1) toward the first 20-hour milestone. Empty = all dark,
/// complete = all light. The filled left end is rounded by the pill; the
/// filled/unfilled boundary is a clean vertical edge. Name centred, Inter bold
/// 12, white. Pure greyscale — fill and remainder are a brightness step apart.
class _TaskPill extends StatelessWidget {
  const _TaskPill({
    required this.label,
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double progress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final remainder = Color.lerp(tokens.surface, tokens.ringTrack, 0.5)!;
    final fill = Color.lerp(tokens.ringTrack, tokens.ringFillInner, 0.35)!;
    final nameStyle = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 20,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: remainder),
              if (progress > 0)
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: ColoredBox(color: fill),
                ),
              // Subtle selected outline; drawn inside the clip so it never
              // changes the pill's exact 20px height. (Not in the measured
              // spec — kept minimal; easy to drop.)
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: tokens.ringFillInner, width: 1.5),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
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
