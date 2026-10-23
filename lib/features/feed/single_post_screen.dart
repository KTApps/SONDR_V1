import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import 'models/post.dart';
import 'widgets/milestone_card.dart';
import 'widgets/session_log_card.dart';

/// One post, on its own page: the card the feed would show, with its Like
/// and Comments where they always are — the cards carry both themselves, so
/// this page is the card, air, and the way back.
///
/// Reached from a profile's strips and grids. A post nobody is allowed to
/// see can never arrive here: the query that found it already required the
/// reader to be in its audience.
class SinglePostScreen extends StatelessWidget {
  const SinglePostScreen({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    final Widget card = switch (post) {
      final MilestonePost p => MilestoneCard(post: p),
      final SessionPost p => SessionLogCard(post: p),
    };
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: kSpacingSection * scale,
            vertical: kSpacingSection * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              SizedBox(height: kSpacingSection * scale),
              Center(
                child: SondrAction(
                  label: 'Back',
                  supporting: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open [post] on its own page.
Future<void> showSinglePost(BuildContext context, Post post) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SinglePostScreen(post: post)),
    );
