import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/duration_format.dart';
import '../../../core/utils/relative_time.dart';
import '../models/post.dart';

/// The tiny card — a single line ("Tom logged 2h 15m · Spanish"). Deliberately
/// minimal so routine activity never drowns the milestones above it. No ring,
/// no like/comment.
class SessionLogCard extends StatelessWidget {
  const SessionLogCard({super.key, required this.post});

  final SessionPost post;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final duration =
        DurationFormat.hm(Duration(seconds: post.sessionSeconds));
    final initial =
        post.author.label.isNotEmpty ? post.author.label[0].toUpperCase() : '?';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: tokens.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: tokens.background,
              child: Text(initial,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: tokens.textSecondary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.textSecondary),
                  children: [
                    TextSpan(
                        text: post.author.label,
                        style: TextStyle(color: tokens.textPrimary)),
                    const TextSpan(text: ' logged '),
                    TextSpan(
                        text: duration,
                        style: TextStyle(color: tokens.textPrimary)),
                    TextSpan(text: ' · ${post.taskName}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (post.createdAt != null) ...[
              const SizedBox(width: 8),
              Text(RelativeTime.of(post.createdAt!),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}
