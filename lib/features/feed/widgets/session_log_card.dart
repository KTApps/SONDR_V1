import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../photos/capture_crop.dart';
import '../firebase_share_backend.dart';
import '../share_job.dart';
import 'milestone_card.dart' show kShareFailedText;

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/utils/session_duration.dart';
import '../models/post.dart';
import 'post_chrome.dart';

/// A session post. Two shapes:
///  - **with a photo** — a functional photo card (author, the session photo,
///    a "task · time" line, caption, like/comment). This is what makes a shared
///    session photo visible (the old card was text-only and dropped the photo).
///  - **no photo** — the slim line `author · task · time`, deliberately minimal
///    so routine activity never drowns the milestones above it. No like/comment.
///
/// Time is [formatSessionDuration] (the shared helper; :30 rounds up). Visual
/// polish of the photo card is deferred (Stage 5) — this is the functional shape.
class SessionLogCard extends ConsumerWidget {
  const SessionLogCard({super.key, required this.post});

  final SessionPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A share of mine that has given up: the caption line says so, and a
    // tap on it tries again.
    final mine = post.authorUid == ref.watch(currentUidProvider);
    final failed = post.pending &&
        mine &&
        ref.watch(shareJobStateProvider(post.id))?.status == ShareJobStatus.failed;
    final retry = failed ? () => ref.read(shareJobRunnerProvider)?.retry(post.id) : null;
    return post.photos.isNotEmpty ? _photo(context, retry) : _slim(context, retry);
  }

  Widget _photo(BuildContext context, VoidCallback? retry) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final line =
        '${post.taskName} · ${formatSessionDuration(post.sessionSeconds)}';
    final caption = retry != null ? kShareFailedText : post.caption;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: tokens.surface,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostAuthorRow(
              author: post.author,
              authorUid: post.authorUid,
              createdAt: post.createdAt,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // 3:4, the shape the photo was framed and stored at. A fixed
              // height cropped it a third time, to a ratio nothing else in
              // the app uses.
              child: AspectRatio(
                aspectRatio: kCaptureAspect,
                child: Image(
                  image: postImageProvider(post.photos.first.url),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              line,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            if (caption != null && caption.isNotEmpty) ...[
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: retry,
                child: Text(caption, style: theme.textTheme.bodyMedium),
              ),
            ],
            const SizedBox(height: 12),
            PostInteractions(post: post),
          ],
        ),
      ),
    );
  }

  Widget _slim(BuildContext context, VoidCallback? retry) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final duration = formatSessionDuration(post.sessionSeconds);
    final initial = post.author.label.isNotEmpty
        ? post.author.label[0].toUpperCase()
        : '?';
    final caption = retry != null ? kShareFailedText : post.caption;
    final hasCaption = caption != null && caption.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: tokens.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Top-align so the avatar + timestamp sit beside the first line when a
        // caption wraps a second line beneath it.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: tokens.background,
              child: Text(
                initial,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // Slim format: author · task · time, middot-separated.
                    '${post.author.label} · ${post.taskName} · $duration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                  // Optional caption as a second line beneath the middot line.
                  if (hasCaption) ...[
                    const SizedBox(height: 2),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: retry,
                      child: Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (post.createdAt != null) ...[
              const SizedBox(width: 8),
              Text(
                RelativeTime.of(post.createdAt!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
