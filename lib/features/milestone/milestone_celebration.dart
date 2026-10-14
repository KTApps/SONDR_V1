import 'package:flutter/material.dart';
import '../../shared/sondr_action.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../shared/ring/progress_ring.dart';
import '../auth/guest_prompts.dart';
import '../photos/models/photo.dart';
import '../../core/utils/duration_format.dart';
import '../photos/capture_flow.dart';
import '../photos/photos_repository.dart';
import '../photos/widgets/collage_grid.dart';

/// Presents the milestone celebration as a full-screen moment.
Future<void> showMilestoneCelebration(
  BuildContext context, {
  required String taskId,
  required String taskName,
  required int milestoneHours,
  required int totalHours,
  required int sessionSeconds,
  required int cumulativeSeconds,
  required bool isFirst,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => MilestoneCelebrationScreen(
        taskId: taskId,
        taskName: taskName,
        milestoneHours: milestoneHours,
        totalHours: totalHours,
        sessionSeconds: sessionSeconds,
        cumulativeSeconds: cumulativeSeconds,
        isFirst: isFirst,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The milestone moment: "Congratulations …", the completed ring (or the band's
/// collage) as hero, then the entry into the share flow. Sharing is offered on
/// **every** 20h crossing now (the first-milestone gate is gone); "Not now"
/// bows out to home — a deliberate opt-out, since users have a right not to
/// broadcast a given task.
///
/// "Share this milestone" leads into: camera-only capture (or skip) → the
/// share-post picker (this band's photos, captured pre-selected) → caption →
/// Create → Feed. See [runCaptureFlow].
class MilestoneCelebrationScreen extends ConsumerStatefulWidget {
  const MilestoneCelebrationScreen({
    super.key,
    required this.taskId,
    required this.taskName,
    required this.milestoneHours,
    required this.totalHours,
    required this.sessionSeconds,
    required this.cumulativeSeconds,
    required this.isFirst,
  });

  final String taskId;
  final String taskName;
  final int milestoneHours;
  final int totalHours;

  /// The crossing session's logged seconds + the task's cumulative-at-crossing —
  /// passed to the capture step so a kept photo lands in the gallery series with
  /// the right session snapshot (as an ordinary end-of-session capture would).
  final int sessionSeconds;
  final int cumulativeSeconds;

  final bool isFirst;

  @override
  ConsumerState<MilestoneCelebrationScreen> createState() =>
      _MilestoneCelebrationScreenState();
}

class _MilestoneCelebrationScreenState
    extends ConsumerState<MilestoneCelebrationScreen> {
  /// The milestone's collage photos, composed live from this milestone's own 20h
  /// band (deterministic — matches the doc that saveAuto persists). Empty when
  /// the band has no photos. Doubles as the share-post pool.
  late final Future<List<Photo>> _collage;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(photosRepositoryProvider);
    _collage = repo == null
        ? Future.value(const <Photo>[])
        : repo.collagePhotos(widget.taskId, widget.milestoneHours);
  }

  /// Enter the share journey: the camera, then review. The band's earlier
  /// captures are offered alongside the new one on the review screen, so
  /// there is no separate picker step any more.
  Future<void> _startShareFlow() async {
    final pool = await _collage;
    if (!mounted) return;
    await runCaptureFlow(
      context,
      ref,
      taskId: widget.taskId,
      taskName: widget.taskName,
      sessionLabel: DurationFormat.hm(
        Duration(seconds: widget.sessionSeconds),
      ),
      sessionSeconds: widget.sessionSeconds,
      cumulativeSeconds: widget.cumulativeSeconds,
      // The band is complete, so the shutter's ring is full.
      ringProgress: 1,
      canShare: true,
      milestoneHours: widget.milestoneHours,
      totalHours: widget.totalHours,
      bandPhotos: pool,
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final isGuest = ref.watch(isGuestProvider);

    final headline = widget.isFirst
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 36),

              // The hero: the milestone's collage when it has photos, else the
              // completed ring (a milestone with zero captures still celebrates).
              FutureBuilder<List<Photo>>(
                future: _collage,
                builder: (ctx, snap) {
                  final photos = snap.data ?? const <Photo>[];
                  if (photos.isEmpty) return _ringHero(theme, tokens);
                  return _collageHero(photos, theme, tokens);
                },
              ),
              const SizedBox(height: 44),

              // Guests can't post — the peak moment doubles as the nudge to
              // create an account.
              if (isGuest) ...[
                Text(
                  'Create an account to keep your progress safe and share it '
                  'with friends.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _Primary(
                label: 'Share this milestone',
                onPressed: isGuest
                    ? () => showCreateAccountPrompt(
                        context,
                        title: 'Keep your progress safe',
                        message:
                            'Create an account to share milestones with '
                            'friends. Your progress stays safe if you delete '
                            'the app or change phones.',
                      )
                    : _startShareFlow,
              ),
              const SizedBox(height: 4),
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

  /// The completed-ring hero — used when the milestone has no photos.
  Widget _ringHero(ThemeData theme, GreyscaleTokens tokens) {
    return ProgressRing(
      size: 260,
      stroke: 260 * 0.09,
      progress: 1.0,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.milestoneHours} hrs',
            style: theme.textTheme.displayMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.taskName,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// The collage hero — the milestone's photos as a grid, with the milestone
  /// figure captioned beneath (since the grid replaces the ring's centre).
  Widget _collageHero(
    List<Photo> photos,
    ThemeData theme,
    GreyscaleTokens tokens,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: CollageGrid(photos: photos),
        ),
        const SizedBox(height: 16),
        Text(
          '${widget.milestoneHours} hours · ${widget.taskName}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Filled greyscale button (matches the timer controls).
class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      Center(child: SondrAction(label: label, onPressed: onPressed));
}
