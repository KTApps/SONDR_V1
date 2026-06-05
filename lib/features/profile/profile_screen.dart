import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../auth/account_screen.dart';

/// The Profile tab. Per the spec it is the home for the effort summary (lifetime
/// hours, current streak, milestones hit), tasks-in-progress, friends, and
/// settings — replacing the phase-1 top-right buttons.
///
/// Step 2 lays down the tab and folds the existing account management
/// ([AccountBody]) in beneath an effort-summary placeholder. The rich summary,
/// friends, and milestones are later sub-steps.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Profile'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _EffortSummaryPlaceholder(),
            // Bounded height so AccountBody's sign-out Spacer has somewhere to
            // push to.
            Expanded(child: AccountBody()),
          ],
        ),
      ),
    );
  }
}

/// Stand-in for the effort summary hero. Replaced by real figures in a later
/// step; here to anchor the layout and signal intent.
class _EffortSummaryPlaceholder extends StatelessWidget {
  const _EffortSummaryPlaceholder();

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Effort summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Your lifetime hours, current streak, and milestones will appear '
              'here.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
