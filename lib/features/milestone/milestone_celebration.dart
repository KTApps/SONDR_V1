import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/ring/ring_dial.dart';

/// Presents the milestone celebration as a full-screen moment.
Future<void> showMilestoneCelebration(
  BuildContext context, {
  required String taskName,
  required int milestoneHours,
  required bool isFirst,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => MilestoneCelebrationScreen(
        taskName: taskName,
        milestoneHours: milestoneHours,
        isFirst: isFirst,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The milestone moment: "Congratulations …", the completed ring as hero with
/// the hours figure, and an optional "Take a photo to mark the moment" (which
/// seeds a feed post in phase 2 — stubbed for now). Triggered every 20 hours,
/// tying to the 20-hour competence philosophy.
class MilestoneCelebrationScreen extends StatelessWidget {
  const MilestoneCelebrationScreen({
    super.key,
    required this.taskName,
    required this.milestoneHours,
    required this.isFirst,
  });

  final String taskName;
  final int milestoneHours;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    final headline = isFirst
        ? "You've reached your first milestone"
        : "You've reached another milestone";

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Congratulations!', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 36),

              // Completed ring as the hero — a full outer ring for the
              // milestone just reached.
              RingDial(
                taskSegments: const [1],
                habitProgress: 0,
                size: 260,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$milestoneHours hrs',
                        style: theme.textTheme.displayMedium),
                    const SizedBox(height: 4),
                    Text(
                      taskName,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 44),

              _Primary(
                label: 'Take a photo to mark the moment',
                onPressed: () => _stubPhoto(context),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  textStyle: theme.textTheme.labelLarge,
                ),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stubPhoto(BuildContext context) {
    // Real capture arrives in phase 2 alongside the feed, where the photo
    // becomes the backdrop of a milestone post (the onPhoto ring variant).
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Photos arrive with the feed in phase 2'),
      ));
  }
}

/// Filled greyscale button (matches the timer controls).
class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.ringFillOuter,
          foregroundColor: tokens.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
        child: Text(label),
      ),
    );
  }
}
