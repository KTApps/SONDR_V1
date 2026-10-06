import 'package:flutter/material.dart';

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
class SessionLogCard extends StatelessWidget {
  const SessionLogCard({super.key, required this.post});

  final SessionPost post;

  @override
  Widget build(BuildContext context) {
    return post.photos.isNotEmpty ? _photo(context) : _slim(context);
  }

  Widget _photo(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final line =
        '${post.taskName} · ${formatSessionDuration(post.sessionSeconds)}';
    final caption = post.caption;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: tokens.surface,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostAuthorRow(author: post.author, createdAt: post.createdAt),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 300,
                width: double.infinity,
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
              Text(caption, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            PostInteractions(post: post),
          ],
        ),
      ),
    );
  }

  Widget _slim(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final duration = formatSessionDuration(post.sessionSeconds);
    final initial = post.author.label.isNotEmpty
        ? post.author.label[0].toUpperCase()
        : '?';
    final caption = post.caption;
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
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
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
