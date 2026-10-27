import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/sondr_action.dart';
import '../feed/band_story.dart' show SegmentUnit;
import '../feed/models/post.dart';
import '../feed/widgets/milestone_card.dart';
import 'capture_review_screen.dart' show ShareState;
import 'share_review_scaffold.dart';

/// The final look: the card exactly as friends will see it — the handle,
/// "now", the pages a tap steps through, the dots, Like and Comments —
/// with the caption typed beneath it and appearing on the card as it is
/// typed. Share posts it; Keep saves the shot privately instead; Back
/// returns to Arrange with everything kept. A guest is told what is
/// missing where Share would be, and offered Keep alone.

enum FinalLookOutcomeKind { back, kept, shared }

@immutable
class FinalLookOutcome {
  const FinalLookOutcome(this.kind);
  final FinalLookOutcomeKind kind;
}

/// The caption field's key, as the scaffold names it.
const Key kFinalLookCaptionKey = kShareReviewCaptionKey;

class MilestoneFinalLookScreen extends StatelessWidget {
  const MilestoneFinalLookScreen({
    super.key,
    required this.photos,
    required this.milestoneHours,
    required this.taskName,
    required this.handle,
    this.share = ShareState.allowed,
    this.segments = const [],
    this.unit,
    this.onKeep,
    this.onShare,
  });

  /// The post's photos in the arranged order, each with its framing and
  /// its session; the new shot as a file:// URL until it is uploaded.
  final List<PostPhoto> photos;
  final int milestoneHours;
  final String taskName;

  /// Whose card it is: the handle the top row prints.
  final String handle;

  /// Whether Share is offered, and what to say when it is not.
  final ShareState share;

  /// The band's story, so the photo pages say their sessions as the
  /// posted card will.
  final List<PostSegment> segments;
  final SegmentUnit? unit;

  /// Saves the shot privately. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref)? onKeep;

  /// Posts with [caption]. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref, String? caption)? onShare;

  /// The post as it will be, for the card to draw.
  MilestonePost _preview(String? caption) => MilestonePost(
    id: 'preview',
    // Not the viewer's own: friends see Like, not Likes.
    authorUid: 'preview',
    author: PostAuthor(username: handle, displayName: ''),
    createdAt: DateTime.now(),
    caption: caption,
    photos: photos,
    taskName: taskName,
    milestoneHours: milestoneHours,
    totalHours: milestoneHours,
    segments: segments,
    unit: unit,
  );

  @override
  Widget build(BuildContext context) {
    return ShareReviewScaffold(
      leading: Builder(
        builder: (context) => SondrAction(
          label: 'Back',
          supporting: true,
          fontSize: 14,
          onPressed: () => Navigator.of(context).pop(const FinalLookOutcome(FinalLookOutcomeKind.back)),
        ),
      ),
      card: (caption) => MilestoneCard(post: _preview(caption), opensPost: false, preview: true),
      lockedCopy: share.canShare ? null : share.lockedCopy,
      onShare: onShare,
      onKeep: onKeep,
      onFinished: (result) => Navigator.of(context).pop(
        FinalLookOutcome(
          result == ShareReviewResult.shared ? FinalLookOutcomeKind.shared : FinalLookOutcomeKind.kept,
        ),
      ),
    );
  }
}
