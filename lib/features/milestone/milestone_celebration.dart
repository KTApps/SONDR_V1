import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/ring/progress_ring.dart';
import '../feed/posts_repository.dart';
import '../photos/photo_picker.dart';

/// Presents the milestone celebration as a full-screen moment.
Future<void> showMilestoneCelebration(
  BuildContext context, {
  required String taskName,
  required int milestoneHours,
  required int totalHours,
  required bool isFirst,
  required bool canShare,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => MilestoneCelebrationScreen(
        taskName: taskName,
        milestoneHours: milestoneHours,
        totalHours: totalHours,
        isFirst: isFirst,
        canShare: canShare,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The milestone moment: "Congratulations …", the completed ring as hero with
/// the hours figure, then the **share-or-not** choice. Sharing is the default
/// action (with or without a photo); dismissing posts nothing — a deliberate
/// opt-out, since users have a right not to broadcast a given task.
///
/// [canShare] gates the post flow; it's currently true only for the first 20h
/// milestone (the widening milestone ladder is a later step). When false, the
/// screen is just the celebratory moment with no posting.
class MilestoneCelebrationScreen extends ConsumerStatefulWidget {
  const MilestoneCelebrationScreen({
    super.key,
    required this.taskName,
    required this.milestoneHours,
    required this.totalHours,
    required this.isFirst,
    required this.canShare,
  });

  final String taskName;
  final int milestoneHours;
  final int totalHours;
  final bool isFirst;
  final bool canShare;

  @override
  ConsumerState<MilestoneCelebrationScreen> createState() =>
      _MilestoneCelebrationScreenState();
}

class _MilestoneCelebrationScreenState
    extends ConsumerState<MilestoneCelebrationScreen> {
  bool _busy = false;

  Future<void> _share({required bool withPhoto}) async {
    final repo = ref.read(postsRepositoryProvider);
    if (repo == null) {
      _toast('Sign in to share milestones.');
      return;
    }

    // Capture + upload first (if asked), so the post is created once, already
    // carrying its photo — friends never see a photoless flash.
    String? photoUrl;
    if (withPhoto) {
      final file = await pickAndDownscale(context);
      if (file == null) return; // backed out, or the pick failed
      setState(() => _busy = true);
      try {
        photoUrl = await repo.uploadPostPhoto(file);
      } catch (e) {
        debugPrint('SONDR photo upload error: $e');
        if (mounted) {
          setState(() => _busy = false);
          _toast('Couldn’t upload the photo. Please try again.');
        }
        return;
      }
    } else {
      setState(() => _busy = true);
    }

    try {
      await repo.createMilestonePost(
        taskName: widget.taskName,
        milestoneHours: widget.milestoneHours,
        totalHours: widget.totalHours,
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      Navigator.of(context).maybePop();
      _toast(withPhoto ? 'Milestone shared with your photo.' : 'Milestone shared.');
    } catch (e) {
      debugPrint('SONDR milestone post error: $e');
      if (mounted) {
        setState(() => _busy = false);
        _toast('Couldn’t share the milestone. Please try again.');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

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
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 36),

              // Completed ring as the hero — a full outer ring for the
              // milestone just reached.
              ProgressRing(
                size: 260,
                stroke: 260 * 0.09,
                progress: 1.0,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${widget.milestoneHours} hrs',
                        style: theme.textTheme.displayMedium),
                    const SizedBox(height: 4),
                    Text(
                      widget.taskName,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 44),

              if (widget.canShare) ..._shareActions(tokens, theme) else
                _dismiss(tokens, theme, label: 'Done'),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _shareActions(GreyscaleTokens tokens, ThemeData theme) {
    return [
      _Primary(
        label: 'Share with a photo',
        busy: _busy,
        onPressed: _busy ? null : () => _share(withPhoto: true),
      ),
      const SizedBox(height: 10),
      _Secondary(
        label: 'Share without a photo',
        onPressed: _busy ? null : () => _share(withPhoto: false),
      ),
      const SizedBox(height: 4),
      _dismiss(tokens, theme, label: 'Not now'),
    ];
  }

  Widget _dismiss(GreyscaleTokens tokens, ThemeData theme,
      {required String label}) {
    return TextButton(
      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
      style: TextButton.styleFrom(
        foregroundColor: tokens.textSecondary,
        textStyle: theme.textTheme.labelLarge,
      ),
      child: Text(label),
    );
  }
}

/// Filled greyscale button (matches the timer controls).
class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

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
          disabledBackgroundColor: tokens.ringTrack,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}

/// Outlined greyscale button for the secondary share action.
class _Secondary extends StatelessWidget {
  const _Secondary({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          side: BorderSide(color: tokens.ringTrack),
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
