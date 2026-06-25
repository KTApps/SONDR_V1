import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/ring/progress_ring.dart';
import '../auth/account_screen.dart';
import '../friends/friends_repository.dart';
import '../friends/friends_screen.dart';
import '../habits/habits_providers.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'profile_providers.dart';

/// The Profile tab. Per the spec the hero is an effort summary — lifetime hours,
/// current streak, milestones hit — followed by tasks-in-progress as mini rings
/// (answering "what is this person working on and how far have they got").
/// Account management is folded in at the bottom. NOT a photo grid.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifetime = ref.watch(lifetimeDurationProvider);
    final streak = ref.watch(habitStreakProvider);
    final milestones = ref.watch(milestonesReachedProvider);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Profile'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EffortSummary(
                lifetime: lifetime,
                streak: streak,
                milestones: milestones,
              ),
              const SizedBox(height: 12),
              const _FriendsRow(),
              const SizedBox(height: 28),
              _TasksInProgress(tasks: tasks),
              const SizedBox(height: 8),
              // Account management (handle, sign in/out) lives here in phase 2.
              const AccountBody(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero: three figures across one card — total lifetime hours, current day
/// streak, milestones reached. Brightness, not colour, carries the emphasis.
class _EffortSummary extends StatelessWidget {
  const _EffortSummary({
    required this.lifetime,
    required this.streak,
    required this.milestones,
  });

  final Duration lifetime;
  final int streak;
  final int milestones;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final hours = (lifetime.inMinutes / 60).round();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(value: '$hours', label: hours == 1 ? 'hour' : 'hours'),
          ),
          _Divider(tokens: tokens),
          Expanded(
            child: _Stat(value: '$streak', label: 'day streak'),
          ),
          _Divider(tokens: tokens),
          Expanded(
            child: _Stat(
              value: '$milestones',
              label: milestones == 1 ? 'milestone' : 'milestones',
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable row into the Friends hub, showing the friend count and a badge for
/// any requests awaiting the user.
class _FriendsRow extends ConsumerWidget {
  const _FriendsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final count = ref.watch(friendCountProvider);
    final pending = ref.watch(incomingRequestsProvider).length;

    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.people_outline, color: tokens.textSecondary),
              const SizedBox(width: 14),
              Text('Friends', style: theme.textTheme.bodyLarge),
              const Spacer(),
              if (pending > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.ringFillOuter,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pending new',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: tokens.background),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text('$count',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: tokens.textSecondary)),
              Icon(Icons.chevron_right, color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium
              ?.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.tokens});
  final GreyscaleTokens tokens;
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: tokens.ringTrack);
}

/// Tasks-in-progress: one mini ring per task filling toward its current 20-hour
/// milestone band (same semantics as the home dial), the task's lifetime hours
/// in the centre. A wrap so any number of tasks lays out tidily.
class _TasksInProgress extends StatelessWidget {
  const _TasksInProgress({required this.tasks});
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('In progress', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Start a task on the timer to see it climb here.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
          )
        else
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [for (final t in tasks) _TaskTile(task: t)],
          ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final hours = (task.total.inMinutes / 60).round();
    final reached = task.milestonesReached;

    return SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressRing(
            size: 72,
            progress: task.milestoneProgress,
            center: Text(
              '${hours}h',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: tokens.textPrimary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            task.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
          ),
          Text(
            reached == 0 ? 'of ${task.activeMilestoneHours}h' : '$reached × 20h',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
          ),
        ],
      ),
    );
  }
}
