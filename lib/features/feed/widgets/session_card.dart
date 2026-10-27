import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/duration_format.dart';
import '../../photos/capture_crop.dart';
import '../../photos/collage_selection.dart' show kMilestoneBandSeconds;
import '../firebase_share_backend.dart';
import '../models/post.dart';
import '../share_job.dart';
import '../single_post_screen.dart';
import 'milestone_card.dart' show kShareFailedText;
import 'milestone_frame.dart' show kMilestoneScrim;
import 'post_card_chrome.dart';
import 'post_chrome.dart';

/// A session post, in the milestone card's frame: the photo full-bleed
/// under the eased scrim, the handle and how long ago above, the task and
/// its length, the caption and the actions below — and, where the dots
/// would be, a small ring filled to how far into its band the task stood.
/// One photo, no pages: a tap anywhere opens the post on its own page.
/// A post from before, with no photo, is the surface with the same text.
class SessionCard extends ConsumerWidget {
  const SessionCard({
    super.key,
    required this.post,
    this.opensPost = true,
    this.preview = false,
  });

  final SessionPost post;

  /// Whether a tap opens the post on its own page. Off on that page.
  final bool opensPost;

  /// The review before a share: the handle and the actions are drawn as
  /// they will be but do nothing.
  final bool preview;

  /// How far into its band the task stood: the ring's fill, 0..1. Null on
  /// a post from before the figure was stored — no ring then.
  double? get bandFill {
    final s = post.bandSeconds;
    if (s == null) return null;
    return (s / kMilestoneBandSeconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final photo = post.photos.isNotEmpty ? post.photos.first : null;
    final onPhoto = photo != null && photo.url.isNotEmpty;
    final mine = post.authorUid == ref.watch(currentUidProvider);
    final shareFailed = post.pending &&
        mine &&
        ref.watch(shareJobStateProvider(post.id))?.status == ShareJobStatus.failed;

    return ClipRRect(
      borderRadius: BorderRadius.circular(kPostCardRadius),
      child: AspectRatio(
        aspectRatio: kCaptureAspect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: opensPost ? () => showSinglePost(context, post) : null,
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
              Positioned(
                left: kPostCardInset,
                right: kPostCardInset,
                top: kPostCardTop,
                child: AbsorbPointer(absorbing: preview, child: PostCardTopRow(post: post)),
              ),
              Positioned(
                left: kPostCardInset,
                right: kPostCardInset,
                // The actions carry 12 of their own below the words; the
                // words' line ends 16 from the edge.
                bottom: kPostCardBottom - PostInteractions.verticalPad,
                child: AbsorbPointer(
                  absorbing: preview,
                  child: _Bottom(
                    post: post,
                    fill: bandFill,
                    shareFailed: shareFailed,
                    onRetry: () => ref.read(shareJobRunnerProvider)?.retry(post.id),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The band ring's measures: Ø26, a 2.5 stroke, the fill on its track,
/// the whole at 85%.
const double kSessionRingSize = 26;
const double kSessionRingStroke = 2.5;
const Color kSessionRingFill = Color(0xFFADADAD);
const Color kSessionRingTrack = Color(0xFF3A3A3A);
const double kSessionRingOpacity = 0.85;

/// The task and its length, the caption, and the actions at the left with
/// the band ring at the right, on the words' baseline.
class _Bottom extends StatelessWidget {
  const _Bottom({
    required this.post,
    required this.fill,
    required this.shareFailed,
    required this.onRetry,
  });

  final SessionPost post;
  final double? fill;
  final bool shareFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final caption = shareFailed ? kShareFailedText : post.caption;
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
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kPostCardText),
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 3),
          if (shareFailed)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: kPostCardTextCaption),
              ),
            )
          else
            IgnorePointer(
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: kPostCardTextCaption),
              ),
            ),
        ],
        // Nothing declared: the actions' own 12 above the words is the 12.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostInteractions(post: post, onPhoto: true),
            const Spacer(),
            if (fill != null)
              IgnorePointer(
                child: Padding(
                  // The ring stands on the words' baseline, as the dots do.
                  padding: EdgeInsets.only(
                    top: math.max(0, PostInteractions.wordBaseline(context) - kSessionRingSize),
                  ),
                  child: SessionBandRing(fill: fill!),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The band ring: the track, and the fill clockwise from 12.
class SessionBandRing extends StatelessWidget {
  const SessionBandRing({super.key, required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: kSessionRingOpacity,
      child: SizedBox(
        width: kSessionRingSize,
        height: kSessionRingSize,
        child: CustomPaint(painter: _RingPainter(fill)),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fill);
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(kSessionRingStroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kSessionRingStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = kSessionRingTrack);
    if (fill > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fill, false, paint..color = kSessionRingFill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fill != fill;
}
