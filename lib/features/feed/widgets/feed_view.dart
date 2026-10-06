import 'package:flutter/material.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../models/post.dart';
import 'deletable_post_card.dart';
import 'milestone_card.dart';
import 'session_log_card.dart';
import 'streak_card.dart';

/// Renders a list of posts as the feed. The card type carries the rhythm — big
/// milestones, medium streaks, tiny session logs — so the list itself is just a
/// chronological column.
class FeedView extends StatelessWidget {
  const FeedView({super.key, required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return const _Empty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: posts.length,
      separatorBuilder: (_, _) =>
          SizedBox(height: kSpacingSection * figmaScale(context)),
      itemBuilder: (context, i) {
        final post = posts[i];
        final Widget card = switch (post) {
          final MilestonePost p => MilestoneCard(post: p),
          final StreakPost p => StreakCard(post: p),
          final SessionPost p => SessionLogCard(post: p),
        };
        // Wrap for long-press-to-delete on the viewer's own posts.
        return DeletablePostCard(post: post, child: card);
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No glyph: the sentence is the empty state.
            Text(
              'When your friends hit milestones, they\u2019ll show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * figmaScale(context),
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
