import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../tasks/models/task.dart';
import '../../tasks/tasks_providers.dart';
import '../timer_controller.dart';

/// Sentinel menu values.
const String _collectiveValue = '__collective__';
const String _addTaskValue = '__add_task__';

/// Top-of-screen task switcher with two modes:
///
///  * **"Task"** (collective overview) — the default; the dial shows every
///    task's day-split and is view-only.
///  * A **specific task** — the centre follows it and the timer controls appear.
///
/// The menu lists the collective entry, then each task with a small bar showing
/// its progress toward its first 20-hour milestone (the only place milestone
/// progress is shown), then "Add task". **Double-tapping** the selector snaps
/// straight back to collective mode without opening the menu. The whole control
/// is locked while a timer session is active, so logged time can't be
/// misattributed by switching mid-session.
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
        // Double-tap only matters when a specific task is selected; offering it
        // in collective mode would needlessly delay the single tap.
        onDoubleTap:
            (locked || isCollective) ? null : _snapToCollective,
        child: Container(
          key: _selectorKey,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down, color: tokens.textSecondary),
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
    final tokens = GreyscaleTokens.of(context);
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    final selectedId = ref.read(selectedTaskIdProvider);

    final position = _menuPosition();
    if (position == null) return;

    final result = await showMenu<String>(
      context: context,
      position: position,
      color: tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<String>(
          value: _collectiveValue,
          child: _CollectiveRow(selected: selectedId == null),
        ),
        const PopupMenuDivider(),
        for (final task in tasks)
          PopupMenuItem<String>(
            value: task.id,
            child: _TaskRow(task: task, selected: task.id == selectedId),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: _addTaskValue,
          child: Row(
            children: [
              Icon(Icons.add, size: 20, color: tokens.textSecondary),
              const SizedBox(width: 10),
              Text('Add task', style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );

    if (!mounted || result == null) return;
    switch (result) {
      case _collectiveValue:
        _snapToCollective();
      case _addTaskValue:
        await _promptAddTask();
      default:
        ref.read(selectedTaskIdProvider.notifier).select(result);
    }
  }

  /// Position the menu just below the selector.
  RelativeRect? _menuPosition() {
    final selectorBox =
        _selectorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (selectorBox == null || overlayBox == null) return null;
    final topLeft = selectorBox.localToGlobal(
      Offset(0, selectorBox.size.height + 4),
      ancestor: overlayBox,
    );
    final bottomRight = selectorBox.localToGlobal(
      selectorBox.size.bottomRight(const Offset(0, 4)),
      ancestor: overlayBox,
    );
    return RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlayBox.size,
    );
  }

  Future<void> _promptAddTask() async {
    final controller = TextEditingController();
    final tokens = GreyscaleTokens.of(context);

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          title: const Text('Add task'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Spanish'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
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

/// The collective "Task" overview entry.
class _CollectiveRow extends StatelessWidget {
  const _CollectiveRow({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(Icons.donut_large_outlined, size: 20, color: tokens.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Task',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                Text('All tasks · overview',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: tokens.textTertiary)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check, size: 18, color: tokens.textPrimary),
        ],
      ),
    );
  }
}

/// A task row: name, milestone progress bar (toward the first 20h), and the
/// current hours figure.
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.selected});

  final Task task;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final hours = (task.totalSeconds / 3600).floor();

    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 18, color: tokens.textPrimary),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MilestoneBar(progress: task.firstMilestoneProgress),
              ),
              const SizedBox(width: 8),
              Text(
                '${hours}h',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thin greyscale bar: track + fill toward the first 20-hour milestone.
class _MilestoneBar extends StatelessWidget {
  const _MilestoneBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: tokens.ringTrack)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: ColoredBox(color: tokens.ringFillOuter),
            ),
          ],
        ),
      ),
    );
  }
}
