import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'feed_mocks.dart';
import 'posts_repository.dart';
import 'widgets/feed_view.dart';

/// The Feed tab: a friends-only vertical scroll of milestone / streak / session
/// posts. Wired to the live [feedProvider]; with `--dart-define=MOCK_FEED=true`
/// it renders sample posts instead, for previewing the cards on the simulator.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // No AppBar — the redundant "Feed" title is removed. SafeArea drops the
      // content just below the status bar / Dynamic Island; the small top inset
      // keeps the first card from hugging it.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: kMockFeed
              ? FeedView(posts: mockPosts())
              : ref.watch(feedProvider).when(
                    data: (posts) => FeedView(posts: posts),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const _Error(),
                  ),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error();
  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Couldn’t load the feed. Pull to refresh or try again later.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}
