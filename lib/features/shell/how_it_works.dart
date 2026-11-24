import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/blur_sheet.dart';

/// How each tab works, a line at a time: the words a long-press on a tab
/// label opens, and all three together behind "How sondr works" in More.

/// One point: the lead phrase, in the text tone and bold, then the rest of
/// the sentence in the supporting tone.
@immutable
class HowToLine {
  const HowToLine(this.lead, this.rest);
  final String lead;
  final String rest;

  String get text => '$lead$rest';
}

/// The three tabs, in the bar's order.
enum HowToTab { home, posts, profile }

extension HowToTabWords on HowToTab {
  /// The tab's own name, as the bar prints it.
  String get label => switch (this) {
    HowToTab.home => 'Home',
    HowToTab.posts => 'Posts',
    HowToTab.profile => 'Profile',
  };

  List<HowToLine> get lines => switch (this) {
    HowToTab.home => kHowHomeWorks,
    HowToTab.posts => kHowPostsWork,
    HowToTab.profile => kHowProfileWorks,
  };
}

const List<HowToLine> kHowHomeWorks = [
  HowToLine(
    'Tap Tasks',
    " to pick what you're working on. Double-tap a task's name to see all your tasks again.",
  ),
  HowToLine('Outer ring:', " today's time, split by task. Tap the centre for this month."),
  HowToLine('Inner ring:', ' tap it for your habits.'),
  HowToLine('Lock your phone:', ' the timer keeps going.'),
  HowToLine('Stop', ' to take a photo. Every 20 hours is a milestone.'),
  HowToLine('Swipe a task left', ' to rename or archive it.'),
];

const List<HowToLine> kHowPostsWork = [
  HowToLine("Your friends' posts", ', newest first.'),
  HowToLine('Tap the right side', ' of a milestone to see each photo, the left to go back.'),
  HowToLine('Tap a caption', ' to read all of it.'),
  HowToLine('Hold your own post', ' to delete it.'),
  HowToLine('Notifications', ' are at the top right.'),
];

const List<HowToLine> kHowProfileWorks = [
  HowToLine('Tap your photo', ' to change it.'),
  HowToLine('Your total hours', ', streak and milestones.'),
  HowToLine('Milestones:', ' tap one to see its photos.'),
  HowToLine('In progress:', ' how close each task is to its next 20 hours.'),
  HowToLine('More', ' has settings, camera access and sign out.'),
];

/// The title of the sheet with all three.
const String kHowSondrWorks = 'How sondr works';

/// The gap between two points, and above a heading in the all-three sheet.
const double kHowToLineGap = 12;
const double kHowToSectionGap = 24;

/// One tab's sheet, titled with the tab's own name.
Future<void> showHowToSheet(BuildContext context, HowToTab tab) => showBlurSheet(
  context,
  (_) => BlurView(title: tab.label, body: HowToLines(lines: tab.lines)),
);

/// All three, each under its tab's name.
const BlurView kHowSondrWorksView = BlurView(
  title: kHowSondrWorks,
  body: HowToSections(),
);

/// The points, one to a line, left-aligned in the sheet's column, at the
/// sheet's body size.
class HowToLines extends StatelessWidget {
  const HowToLines({super.key, required this.lines});

  final List<HowToLine> lines;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      fontSize: kBlurExplanationSize * scale,
      color: tokens.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) SizedBox(height: kHowToLineGap * scale),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: lines[i].lead,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                TextSpan(text: lines[i].rest),
              ],
            ),
            textAlign: TextAlign.left,
            style: body,
          ),
        ],
      ],
    );
  }
}

/// Home, Posts and Profile, each heading in the quiet bold the notification
/// page's day headings wear, with its points under it.
class HowToSections extends StatelessWidget {
  const HowToSections({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tab in HowToTab.values) ...[
          if (tab != HowToTab.home) SizedBox(height: kHowToSectionGap * scale),
          Text(
            tab.label,
            textAlign: TextAlign.left,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textTertiary,
            ),
          ),
          SizedBox(height: kHowToLineGap * scale),
          HowToLines(lines: tab.lines),
        ],
      ],
    );
  }
}
