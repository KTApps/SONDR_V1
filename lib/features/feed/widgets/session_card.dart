import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/duration_format.dart';
import '../../photos/capture_crop.dart';
import '../models/post.dart';
import 'milestone_frame.dart' show kMilestoneScrim;
import 'mini_ring.dart';
import 'post_card_chrome.dart';
import 'post_chrome.dart';

/// A session post, in the milestone card's frame: the photo full-bleed
/// under the eased scrim, "First time" at the top right on the task's
/// first ever — who posted it and when stand above the card — the task and
/// its length, the caption and the actions below — and at the right the
/// small ring: grey to where the task stood in its band before this
/// session, white for the session itself. One photo, no pages: a tap on
/// the card does nothing; the caption opens in place when tapped. A post
/// from before, with no photo, is the surface with the same text.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.post,
    this.preview = false,
  });

  final SessionPost post;

  /// The review before a share: the handle and the actions are drawn as
  /// they will be but do nothing.
  final bool preview;

  /// What the ring shows. The stored figure is the task's seconds into
  /// its band AFTER this session, so before it is that less the session.
  /// Null on a post from before the figure was stored — no ring then.
  MiniRingData? get ring => sessionRing(post);

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final photo = post.photos.isNotEmpty ? post.photos.first : null;
    final onPhoto = photo != null && photo.url.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(kPostCardRadius),
      child: AspectRatio(
        aspectRatio: kCaptureAspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (onPhoto)
              Image(
                image: postImageProvider(photo.url),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => ColoredBox(color: tokens.surface),
              )
            else
              ColoredBox(color: tokens.surface),
            if (onPhoto)
              const IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(gradient: kMilestoneScrim)),
              ),
            // The task's first time ever, where how-long-ago used to be.
            if (post.firstSession)
              Positioned(
                right: kPostCardInset,
                top: kPostCardTop,
                child: IgnorePointer(
                  child: Text(
                    kFirstTimeLabel,
                    key: kFirstTimeKey,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                      shadows: kTextShadows,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: kPostCardInset,
              right: kPostCardInset,
              // The actions carry 12 of their own below the words; the
              // words' line ends 16 from the edge.
              bottom: kPostCardBottom - PostInteractions.verticalPad,
              child: AbsorbPointer(
                absorbing: preview,
                child: _Bottom(post: post, ring: ring, onPhoto: onPhoto),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// On a photo from the task's first time ever.
const String kFirstTimeLabel = 'First time';
const Key kFirstTimeKey = ValueKey('post-first-time');

/// What a session post's ring shows, or null when the post has no figure.
MiniRingData? sessionRing(SessionPost post) {
  final after = post.bandSeconds;
  if (after == null) return null;
  return MiniRingData(
    before: math.max(0, after - post.sessionSeconds),
    seconds: post.sessionSeconds,
  );
}

/// The task and its length, the caption, and the actions at the left with
/// the small ring at the right, on the words' baseline.
class _Bottom extends StatelessWidget {
  const _Bottom({required this.post, required this.ring, required this.onPhoto});

  final SessionPost post;
  final MiniRingData? ring;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final caption = post.caption;
    final line = '${post.taskName} · ${DurationFormat.hm(Duration(seconds: post.sessionSeconds))}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          child: Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kPostCardTaskStyle,
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 3),
          PostCardCaption(text: caption),
        ],
        // Nothing declared: the actions' own 12 above the words is the 12.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostInteractions(post: post, onPhoto: true),
            const Spacer(),
            if (ring != null)
              IgnorePointer(
                child: Padding(
                  // The ring stands on the words' baseline.
                  padding: EdgeInsets.only(
                    top: math.max(0, PostInteractions.wordBaseline(context) - kMiniRingSize),
                  ),
                  child: MiniRing(data: ring!, onPhoto: onPhoto),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
