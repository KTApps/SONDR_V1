import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/session_duration.dart';
import '../feed/models/post.dart';
import '../feed/posts_repository.dart';
import '../photos/photo_capture_flow.dart';
import 'share_caption_screen.dart';

/// The 20h+ session share flow (a task past its first milestone stopping without
/// crossing a new one). Lighter than the milestone flow: camera-only capture (or
/// skip) → the shared caption screen with a single-photo (or slim) preview →
/// Create → Feed; back → Home.
///
/// **Single-photo only** — the schema allows a list, but this write path only
/// ever attaches the one captured photo (no journey multi-add). A kept photo has
/// already saved to the task's gallery series inside [showPhotoCapture], so
/// capture and post stay independent.
Future<void> showSessionShareFlow(
  BuildContext context, {
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  required int cumulativeSeconds,
}) async {
  // Camera-only capture (or skip → null); a kept photo is already in the gallery.
  final captured = await showPhotoCapture(
    context,
    taskId: taskId,
    taskName: taskName,
    sessionSeconds: sessionSeconds,
    cumulativeSeconds: cumulativeSeconds,
  );
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SharePostCaptionScreen(
        submitLabel: 'Share',
        preview: _SessionPreview(
          capturedFile: captured,
          taskName: taskName,
          sessionSeconds: sessionSeconds,
        ),
        onSubmit: (ref, caption) async {
          final repo = ref.read(postsRepositoryProvider);
          if (repo == null) throw StateError('not signed in');
          final photos = <PostPhoto>[];
          if (captured != null) {
            final up = await repo.uploadPostPhoto(captured);
            photos.add(PostPhoto(url: up.url, storagePath: up.storagePath));
          }
          await repo.createSessionPost(
            taskName: taskName,
            sessionSeconds: sessionSeconds,
            caption: caption,
            photos: photos,
          );
        },
      ),
    ),
  );
}

/// The caption-screen preview for a session post: the one captured photo with a
/// "task · time" line beneath, or — when there's no photo — the slim line alone
/// (matching the photoless SessionPost card).
class _SessionPreview extends StatelessWidget {
  const _SessionPreview({
    required this.capturedFile,
    required this.taskName,
    required this.sessionSeconds,
  });

  final File? capturedFile;
  final String taskName;
  final int sessionSeconds;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final line = '$taskName · ${formatSessionDuration(sessionSeconds)}';

    if (capturedFile != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Image.file(capturedFile!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            line,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        line,
        style: theme.textTheme.bodyLarge?.copyWith(color: tokens.textPrimary),
      ),
    );
  }
}
