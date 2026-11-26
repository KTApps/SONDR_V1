import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../feed_days.dart';
import '../models/post.dart';
import '../posts_repository.dart';
import 'day_card.dart';
import 'deletable_post_card.dart';
import 'milestone_card.dart';
import 'post_card_chrome.dart';

/// The feed: each friend's last day on one card, and every milestone on its
/// own, newest first — a day sorted by its newest photo, so a new one
/// brings that person to the top. Above every card, who posted it and one
/// line about it. Scrolling near the end reads the next page of
/// milestones.
class FeedView extends ConsumerWidget {
  const FeedView({super.key, required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(feedNowProvider)();
    // Re-drawn with the cutoff, so a photo past its day goes as the feed
    // is asked again, not only when the app is opened.
    ref.watch(feedCutoffProvider);
    final items = feedItems(posts, now: now);
    if (items.isEmpty) return const _Empty();
    final more = ref.watch(moreMilestonesProvider);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (more &&
            n.metrics.axis == Axis.vertical &&
            n.metrics.extentAfter < kFeedLoadMoreWithin) {
          ref.read(milestoneLimitProvider.notifier).more();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            SizedBox(height: kSpacingSection * figmaScale(context)),
        itemBuilder: (context, i) => FeedItemView(
          key: ValueKey(items[i].key),
          item: items[i],
          now: now,
        ),
      ),
    );
  }
}

/// How near the end of the list a page more of milestones is read.
const double kFeedLoadMoreWithin = 600;

/// One card with its header.
class FeedItemView extends StatelessWidget {
  const FeedItemView({super.key, required this.item, required this.now});

  final FeedItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (header, card) = switch (item) {
      final DayItem d => (
          PostHeader(author: d.author, authorUid: d.authorUid, line: dayLine(d, now: now)),
          DayCard(posts: d.posts) as Widget,
        ),
      final MilestoneItem m => (
          PostHeader(
            author: m.post.author,
            authorUid: m.post.authorUid,
            line: milestoneLine(m.post, now: now),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDayCardMargin),
            child: DeletablePostCard(post: m.post, child: MilestoneCard(post: m.post)),
          ),
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // Over the words on the photo: the card's margin and its inset.
          padding: const EdgeInsets.symmetric(horizontal: kDayCardMargin + kPostCardInset),
          child: header,
        ),
        card,
      ],
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
