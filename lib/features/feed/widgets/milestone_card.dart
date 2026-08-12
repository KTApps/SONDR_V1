import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../shared/ring/progress_ring.dart';
import '../../../shared/ring/ring_dial.dart';
import '../models/post.dart';
import 'post_chrome.dart';

/// The big card. The completed dual ring is the hero with the milestone-hours
/// figure in its centre. Two surfaces, one layout: a full-bleed photo backdrop
/// (scrim + on-photo rings + white badge) or a plain dark-grey card.
///
/// The inner (habit) ring is left empty — milestone posts carry no habit data,
/// so the real achievement is the full outer (task) ring; we don't invent the
/// inner.
class MilestoneCard extends StatelessWidget {
  const MilestoneCard({super.key, required this.post});

  final MilestonePost post;

  bool get _hasPhoto => post.photos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: _hasPhoto ? _photo(context) : _plain(context),
    );
  }

  static const double _ringSize = 184;

  Widget _ring(BuildContext context, {required bool onPhoto}) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final figureColor = onPhoto ? Colors.white : tokens.textPrimary;
    final shadows = onPhoto ? kTextShadows : null;

    final center = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${post.milestoneHours}',
          style: theme.textTheme.displaySmall?.copyWith(
            color: figureColor,
            shadows: shadows,
          ),
        ),
        Text(
          'hours',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: onPhoto ? Colors.white70 : tokens.textTertiary,
            shadows: shadows,
          ),
        ),
      ],
    );

    // Over a photo: keep the near-white ring + double-stroke halo + scrim
    // treatment exactly — a mid-grey #777 ring would be illegible on a bright
    // photo. (RingDial draws the completed milestone as a full outer ring.)
    if (onPhoto) {
      return RingDial(
        size: _ringSize,
        taskSegments: const [1.0], // the completed milestone
        highlightedSegment: 0,
        habitProgress: 0.0,
        showInnerRing: false, // milestone posts carry no habit data
        onPhoto: true,
        center: center,
      );
    }

    // On a plain card: a completed milestone is a full #777777 ring (#232323
    // remainder) via ProgressRing, matching the dial/profile scheme. Stroke is
    // matched to the photo card's ring weight (RingDial's 0.09×size) so photo
    // and no-photo milestone cards read consistently.
    return ProgressRing(
      size: _ringSize,
      stroke: _ringSize * 0.09,
      progress: 1.0,
      center: center,
    );
  }

  Widget _badge(BuildContext context, {required bool onPhoto}) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final bg = onPhoto ? Colors.white : tokens.ringTrack;
    final fg = onPhoto ? Colors.black : tokens.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Milestone · ${post.milestoneHours}h',
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _caption(BuildContext context, {required bool onPhoto}) {
    final caption = post.caption;
    if (caption == null || caption.isEmpty) return const SizedBox.shrink();
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        caption,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: onPhoto ? Colors.white : tokens.textSecondary,
          shadows: onPhoto ? kTextShadows : null,
        ),
      ),
    );
  }

  Widget _plain(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Container(
      color: tokens.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostAuthorRow(author: post.author, createdAt: post.createdAt),
          const SizedBox(height: 16),
          _badge(context, onPhoto: false),
          const SizedBox(height: 16),
          Center(child: _ring(context, onPhoto: false)),
          _caption(context, onPhoto: false),
          const SizedBox(height: 16),
          PostInteractions(post: post),
        ],
      ),
    );
  }

  Widget _photo(BuildContext context) {
    return SizedBox(
      height: 460,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // First photo as the full-bleed backdrop. Multi-photo milestone card
          // layout is a later stage; for now the hero is photos.first.
          Image(
            image: postImageProvider(post.photos.first.url),
            fit: BoxFit.cover,
          ),
          // Scrim: darker top & bottom (where text/icons sit), lighter middle
          // (where the ring sits). Baked in so bright photos stay legible.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0x22000000),
                  Color(0x22000000),
                  Color(0xAA000000),
                ],
                stops: [0.0, 0.32, 0.62, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PostAuthorRow(
                  author: post.author,
                  createdAt: post.createdAt,
                  onPhoto: true,
                ),
                const SizedBox(height: 12),
                _badge(context, onPhoto: true),
                Expanded(child: Center(child: _ring(context, onPhoto: true))),
                _caption(context, onPhoto: true),
                const SizedBox(height: 12),
                PostInteractions(post: post, onPhoto: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
