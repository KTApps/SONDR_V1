import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../photos/capture_crop.dart';
import '../milestone_hints.dart';
import '../milestone_pages.dart';
import '../models/post.dart';
import 'mini_ring.dart';
import 'milestone_cover.dart';
import 'milestone_frame.dart';
import 'post_card_chrome.dart';
import 'post_chrome.dart';

/// The milestone card: one 3:4 frame, the handle above and the task below,
/// the ring at its height — the one shape every milestone takes, whether
/// it has no photo, one, or a band's worth.
///
/// The first page is the cover: the band's photos as a collage under the
/// scrim and the ring, rendered once at share time and shown as one image,
/// or drawn here for a post from before covers. A tap on the right third
/// steps to the photos one by one — each full-bleed under the scrim, the
/// task line saying how long that session was and the small ring at the
/// right how far into the band it stood — and from the last photo back to
/// the cover; the left third steps back, and the cover stays put; the
/// middle does nothing. The caption opens in place when tapped. No
/// swiping: the feed owns the drag.
///
/// Numbers here are the mockup's at the card's width and are not scaled,
/// as the ring never was: the card is a fixed composition over a photo.
class MilestoneCard extends ConsumerStatefulWidget {
  const MilestoneCard({
    super.key,
    required this.post,
    this.preview = false,
  });

  final MilestonePost post;

  /// The final look before a share: the handle and the actions are drawn
  /// as they will be but do nothing — there is no post yet to like, and
  /// the pages still step.
  final bool preview;

  @override
  ConsumerState<MilestoneCard> createState() => _MilestoneCardState();
}

/// The frame's corner, as the milestone card has always been cut.
const double kMilestoneCardRadius = kPostCardRadius;

/// What the caption line says while the hint is on.
const String kMilestoneHintText = 'Tap the right side to see each session';

const double _kInset = kPostCardInset;
const double _kTop = kPostCardTop;
const double _kBottom = kPostCardBottom;
const Color _kTextCaption = kPostCardTextCaption;

/// The hint's glow on the right third: white, to 14% at its brightest,
/// easing in and out over 1.6 seconds, twice.
const double kMilestoneHintGlow = 0.14;
const Duration kMilestoneHintCycle = Duration(milliseconds: 1600);
const int kMilestoneHintCycles = 2;

class _MilestoneCardState extends ConsumerState<MilestoneCard>
    with SingleTickerProviderStateMixin {
  int _page = 0;

  /// The glow: 0 → 1 → 0 is one cycle. Built in initState, not lazily: a
  /// card that never shows the hint would otherwise CREATE the controller
  /// on the way out, looking up an ancestor it no longer has.
  late final AnimationController _glow;
  bool _glowStarted = false;
  bool _seenMarked = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(vsync: this, duration: kMilestoneHintCycle ~/ 2);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  List<MilestonePage> get _pages => milestonePages(widget.post);

  bool get _multi => widget.post.photos.length > 1;

  /// On: the next photo, and from the last one round to the cover.
  void _next() {
    setState(() => _page = _page < _pages.length - 1 ? _page + 1 : 0);
  }

  /// Back: the previous page; the cover stays put.
  void _previous() {
    if (_page > 0) setState(() => _page--);
  }

  /// Where a tap landed: the right third steps on, the left back, the
  /// middle nothing. A single photo has nowhere to step.
  void _tap(Offset at, double width) {
    final pages = _pages;
    if (pages.length < 2) return;
    if (at.dx > width * 2 / 3) {
      _next();
      _foundTheGesture();
    } else if (at.dx < width / 3) {
      _previous();
    }
  }

  /// The right side was tapped: the hint has done its job, on every card.
  void _foundTheGesture() {
    if (widget.preview) return;
    final hints = ref.read(milestoneHintsProvider);
    hints.markTapped().then((_) {
      if (mounted) ref.invalidate(milestoneHintStateProvider);
    });
  }

  /// Whether the hint is on for this card: a multi-photo post, on the
  /// cover, that the hint belongs on.
  bool _hintOn(MilestoneHintState? state) =>
      !widget.preview &&
      _multi &&
      _page == 0 &&
      state != null &&
      state.showFor(widget.post.id);

  void _startHint() {
    if (!_seenMarked) {
      _seenMarked = true;
      final hints = ref.read(milestoneHintsProvider);
      hints.markSeen(widget.post.id).then((_) {
        if (mounted) ref.invalidate(milestoneHintStateProvider);
      });
    }
    if (!_glowStarted) {
      _glowStarted = true;
      _glow.repeat(reverse: true, count: kMilestoneHintCycles * 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final pages = _pages;
    final index = _page.clamp(0, pages.length - 1);
    final page = pages[index];
    final hint = _hintOn(ref.watch(milestoneHintStateProvider).value);
    if (hint) _startHint();

    return ClipRRect(
      borderRadius: BorderRadius.circular(kMilestoneCardRadius),
      child: AspectRatio(
        aspectRatio: kCaptureAspect,
        child: LayoutBuilder(
          builder: (context, c) {
            final frame = Stack(
              fit: StackFit.expand,
              children: [
                _body(context, page, c.biggest),
                if (hint)
                  Positioned(
                    left: c.maxWidth * 2 / 3,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _glow,
                        builder: (_, _) => DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(
                                  alpha: kMilestoneHintGlow *
                                      Curves.easeInOut.transform(_glow.value),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: _kInset,
                  right: _kInset,
                  top: _kTop,
                  child: AbsorbPointer(
                    absorbing: widget.preview,
                    child: PostCardTopRow(post: post),
                  ),
                ),
                Positioned(
                  left: _kInset,
                  right: _kInset,
                  // The actions carry 12 of their own below the words;
                  // the words' line ends 16 from the edge.
                  bottom: _kBottom - PostInteractions.verticalPad,
                  child: AbsorbPointer(
                    absorbing: widget.preview,
                    child: _Bottom(
                      post: post,
                      page: page,
                      hint: hint,
                    ),
                  ),
                ),
              ],
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition, c.maxWidth),
              child: frame,
            );
          },
        ),
      ),
    );
  }

  /// A page's ground. The cover as rendered, or drawn; a photo under the
  /// scrim; the surface when there is nothing to show.
  Widget _body(BuildContext context, MilestonePage page, Size size) {
    final post = widget.post;
    final tokens = GreyscaleTokens.of(context);
    switch (page.kind) {
      case MilestonePageKind.noPhoto:
        return MilestoneNoPhotoFrame(milestoneHours: post.milestoneHours);
      case MilestonePageKind.cover:
        final cover = post.coverUrl;
        if (cover != null && cover.isNotEmpty) {
          // Rendered at share time: the collage, the scrim and the ring
          // are in the picture already.
          return Image(
            image: postImageProvider(cover),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _drawnCover(),
          );
        }
        return _drawnCover();
      case MilestonePageKind.photo:
        final url = post.photos[page.photoIndex!].url;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              ColoredBox(color: tokens.surface)
            else
              Image(
                image: postImageProvider(url),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => ColoredBox(color: tokens.surface),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: kMilestoneScrim),
            ),
          ],
        );
    }
  }

  Widget _drawnCover() {
    final shown = [for (final p in widget.post.photos) if (p.url.isNotEmpty) p];
    return MilestoneCover(
      photos: [for (final p in shown) postImageProvider(p.url)],
      framings: [for (final p in shown) p.framing],
      milestoneHours: widget.post.milestoneHours,
    );
  }
}

/// The task — with the session's length on a photo's page — its caption
/// or the hint, and, on the actions' line, the actions at the left and,
/// on a photo's page, the small ring at the right.
class _Bottom extends StatelessWidget {
  const _Bottom({
    required this.post,
    required this.page,
    required this.hint,
  });

  final MilestonePost post;
  final MilestonePage page;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final caption = hint ? kMilestoneHintText : post.caption;
    final session = pageSession(page, post);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          child: Text(
            pageTaskLine(page, post),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kPostCardTaskStyle,
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 3),
          if (hint)
            IgnorePointer(
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _kTextCaption, shadows: kTextShadows),
              ),
            )
          else
            PostCardCaption(text: caption),
        ],
        // Nothing declared: the actions' own 12 above the words is the 12.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostInteractions(post: post, onPhoto: true),
            const Spacer(),
            if (session != null)
              IgnorePointer(
                child: Padding(
                  // The ring stands on the words' baseline.
                  padding: EdgeInsets.only(
                    top: math.max(0, PostInteractions.wordBaseline(context) - kMiniRingSize),
                  ),
                  child: MiniRing(data: MiniRingData(before: session.before, seconds: session.seconds)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
