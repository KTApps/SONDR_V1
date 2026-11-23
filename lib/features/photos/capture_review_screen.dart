import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/sondr_action.dart';
import '../feed/models/post.dart';
import '../feed/widgets/session_card.dart';
import 'models/photo.dart';
import 'share_review_scaffold.dart';

export 'share_review_scaffold.dart' show kCaptionMaxLength;

/// The band photos chosen, in pool order (chronological).
///
/// Pure, and order-preserving: the post's photos read in the order they were
/// taken, not the order they were tapped. The captured photo is handled
/// separately — it always leads.
List<Photo> selectedBandInOrder(List<Photo> pool, Set<String> selectedIds) => [
  for (final p in pool)
    if (selectedIds.contains(p.id)) p,
];

/// Whether this capture can be posted, and if not, why not.
///
/// A bool said only that Share was absent; the screen has to say what would
/// make it appear, and the two answers are different sentences.
enum ShareState {
  /// Signed in. Any total: a session can be shared from its first minute.
  allowed,

  /// A guest. An account is what is missing.
  guest;

  bool get canShare => this == ShareState.allowed;

  /// What the review screen says in place of Share.
  String get lockedCopy => switch (this) {
    ShareState.allowed => '',
    ShareState.guest => 'Create an account to share',
  };
}

/// What the person did with the capture.
enum ReviewOutcome {
  /// Back to the camera; the shot is discarded.
  retake,

  /// Saved to the private gallery and nothing more.
  kept,

  /// Saved and posted.
  shared,
}

/// Where Share would stand on a signed-in session with no photo.
const String kTakeAPhotoToShare = 'Take a photo to share';

/// A session's review: its final look. Retake at the top right; the
/// session card exactly as friends will see it — the handle, "now", the
/// task and its length, the caption as typed, the band ring — with the
/// bare caption field beneath; Share over Keep. As a guest the reason
/// stands where Share would and Keep is the one action; with no photo,
/// "Take a photo to share" stands there and goes back to the camera.
class CaptureReviewScreen extends StatelessWidget {
  const CaptureReviewScreen({
    super.key,
    required this.shotUrl,
    required this.taskName,
    required this.sessionSeconds,
    required this.share,
    this.bandSeconds,
    this.handle = '',
    this.onKeep,
    this.onShare,
  });

  /// The new photo as a file:// URL, exactly as it will be posted — or
  /// null for a session whose camera was skipped, which cannot post.
  final String? shotUrl;

  final String taskName;
  final int sessionSeconds;

  /// Whether Share is offered, and what to say when it is not.
  final ShareState share;

  /// The task's seconds into its band once this session was credited.
  final int? bandSeconds;

  /// Whose card it is.
  final String handle;

  /// Saves privately. Returns false to keep the screen up on failure.
  final Future<bool> Function(WidgetRef ref)? onKeep;

  /// Posts with [caption]. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref, String? caption)? onShare;

  SessionPost _preview(String? caption) => SessionPost(
    id: 'preview',
    authorUid: 'preview',
    author: PostAuthor(username: handle, displayName: ''),
    createdAt: DateTime.now(),
    caption: caption,
    photos: [
      if (shotUrl != null) PostPhoto(url: shotUrl!, storagePath: ''),
    ],
    taskName: taskName,
    sessionSeconds: sessionSeconds,
    bandSeconds: bandSeconds,
  );

  @override
  Widget build(BuildContext context) {
    return ShareReviewScaffold(
      trailing: Builder(
        builder: (context) => SondrAction(
          label: 'Retake',
          supporting: true,
          fontSize: 14,
          onPressed: () => Navigator.of(context).pop(ReviewOutcome.retake),
        ),
      ),
      card: (caption) => SessionCard(post: _preview(caption), preview: true),
      // A session post is its photo: without one, nothing to share until
      // one is taken — which is what Retake does.
      lockedCopy: !share.canShare
          ? share.lockedCopy
          : shotUrl == null
          ? ''
          : null,
      lockedAction: share.canShare && shotUrl == null
          ? Builder(
              builder: (context) => SondrAction(
                label: kTakeAPhotoToShare,
                quiet: true,
                onPressed: () => Navigator.of(context).pop(ReviewOutcome.retake),
              ),
            )
          : null,
      onShare: onShare,
      onKeep: onKeep,
      onFinished: (result) => Navigator.of(context).pop(
        result == ShareReviewResult.shared ? ReviewOutcome.shared : ReviewOutcome.kept,
      ),
    );
  }
}
