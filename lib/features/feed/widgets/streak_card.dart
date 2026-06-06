import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../models/post.dart';
import 'post_chrome.dart';

/// The medium card. The streak number is the hero; the habit list is small
/// print beneath it.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.post});

  final StreakPost post;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: tokens.surface,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostAuthorRow(author: post.author, createdAt: post.createdAt),
            const SizedBox(height: 16),
            // Hero: the streak number.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${post.streakDays}',
                    style: theme.textTheme.displayMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('day habit streak',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: tokens.textSecondary)),
              ],
            ),
            if (post.habits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post.habits.join('  ·  '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tokens.textTertiary),
              ),
            ],
            if ((post.caption ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(post.caption!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.textSecondary)),
            ],
            const SizedBox(height: 16),
            PostInteractions(post: post),
          ],
        ),
      ),
    );
  }
}
