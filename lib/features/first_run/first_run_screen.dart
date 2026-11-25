import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/blur_sheet.dart';
import '../../shared/sondr_action.dart';
import '../shell/how_it_works.dart';
import '../shell/main_shell.dart';
import '../timer/home_metrics.dart';
import 'first_run.dart';

/// Where the copy block starts, from the top of the screen.
const double kFirstRunCopyTop = 176;

/// Between two lines, and the extra under the title.
const double kFirstRunLineGap = 18;
const double kFirstRunTitleExtra = 6;

/// Between the hint and the tab names under it.
const double kFirstRunHintGap = 12;

const String kFirstRunHint = 'Hold any of these to see how that screen works.';

/// Onboarding, or "What's new": a title, a few lines, Continue, and the
/// three tab names where the tab bar will be. Full screen, no tab bar.
class FirstRunScreen extends StatelessWidget {
  const FirstRunScreen({
    super.key,
    required this.view,
    required this.onContinue,
  });

  final FirstRunView view;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    // The how-to sheets' own type: their title, and their line.
    final body = howToLineStyle(context);

    return Scaffold(
      backgroundColor: tokens.background,
      body: Stack(
        children: [
          Positioned(
            top: kFirstRunCopyTop * scale,
            left: 24 * scale,
            right: 24 * scale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.title,
                  key: kFirstRunTitleKey,
                  style: blurTitleStyle(context),
                ),
                SizedBox(
                  height: (kFirstRunLineGap + kFirstRunTitleExtra) * scale,
                ),
                for (var i = 0; i < view.lines.length; i++) ...[
                  if (i > 0) SizedBox(height: kFirstRunLineGap * scale),
                  Text(
                    view.lines[i],
                    style: body?.copyWith(
                      // The first line says what Sondr is; the rest, how.
                      color: i == 0 ? tokens.textPrimary : tokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            // Home's Pause and Stop row's top, so Continue is on that line.
            top: kHomeActionTop * scale,
            left: 0,
            right: 0,
            child: Center(
              child: SondrAction(
                key: kFirstRunContinueKey,
                label: 'Continue',
                onPressed: onContinue,
              ),
            ),
          ),
        ],
      ),
      // In the tab bar's own slot, so the names land where its labels do.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * scale),
            child: Text(
              kFirstRunHint,
              key: kFirstRunHintKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * scale,
                color: tokens.textSecondary,
              ),
            ),
          ),
          SizedBox(height: kFirstRunHintGap * scale),
          const TextTabBar.names(key: kFirstRunTabNamesKey),
        ],
      ),
    );
  }
}

const Key kFirstRunTitleKey = ValueKey('first-run-title');
const Key kFirstRunContinueKey = ValueKey('first-run-continue');
const Key kFirstRunHintKey = ValueKey('first-run-hint');
const Key kFirstRunTabNamesKey = ValueKey('first-run-tab-names');
