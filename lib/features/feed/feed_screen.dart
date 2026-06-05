import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';

/// The Feed tab. Placeholder for now — the real feed (milestone / streak /
/// session-log cards) is a later phase-2 sub-step. Kept as its own screen so
/// the tab shell is complete and the feed slots straight in.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Feed'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dynamic_feed_outlined,
                    size: 48, color: tokens.textTertiary),
                const SizedBox(height: 16),
                Text(
                  'Your friends’ effort will appear here',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
