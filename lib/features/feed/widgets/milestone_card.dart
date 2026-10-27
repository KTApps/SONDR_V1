import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/relative_time.dart';
import '../../photos/capture_crop.dart';
import '../../profile/other_profile_screen.dart';
import '../milestone_hints.dart';
import '../milestone_pages.dart';
import '../models/post.dart';
import '../single_post_screen.dart';
import 'milestone_cover.dart';
import 'milestone_frame.dart';
import 'milestone_ring.dart';
import 'post_chrome.dart';

/// The milestone card: one 3:4 frame, the handle above and the task below,
/// the ring at its height — the one shape every milestone takes, whether
/// it has no photo, one, or a band's worth.
///
/// The first page is the cover: the band's photos as a collage under the
/// scrim and the ring, rendered once at share time and shown as one image,
/// or drawn here for a post from before covers. A tap on the right third
/// steps to the photos one by one — each full-bleed, the ring saying how
/// long that session was and when — the left third steps back, and the
/// middle opens the post on its own page. No swiping: the feed owns the
/// drag.
///
/// Numbers here are the mockup's at the card's width and are not scaled,
/// as the ring never was: the card is a fixed composition over a photo.
class MilestoneCard extends ConsumerStatefulWidget {
  const MilestoneCard({super.key, required this.post, this.opensPost = true});

  final MilestonePost post;

  /// Whether a tap in the middle opens the post on its own page. Off on
  /// that page.
  final bool opensPost;

  @override
  ConsumerState<MilestoneCard> createState() => _MilestoneCardState();
}

/// The frame's corner, as the milestone card has always been cut.
const double kMilestoneCardRadius = 24;

/// What the caption line says while the hint is on.
const String kMilestoneHintText = 'Tap the right side to see each session';

/// Air from the frame's edge to the text.
const double _kInset = 18;
const double _kTop = 16;
const double _kBottom = 16;

/// Text over the photo. Fixed, not theme tokens: the ground is the photo,
/// not the surface, and the scrim below holds the contrast.
const Color _kText = Color(0xFFFAFAFA);
const Color _kTextTime = Color(0xB3FAFAFA); // 70%
const Color _kTextCaption = Color(0xCCFAFAFA); // 80%
const Color _kDotOther = Color(0x59FAFAFA); // 35%

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

  void _next() {
    if (_page < _pages.length - 1) setState(() => _page++);
  }

  void _previous() {
    if (_page > 0) setState(() => _page--);
  }

  /// Where a tap landed: the right third steps on, the left back, the
  /// middle opens the post. A single photo has nowhere to step, so the
  /// whole card opens the post.
  void _tap(Offset at, double width) {
    final pages = _pages;
    if (pages.length > 1 && at.dx > width * 2 / 3) {
      _next();
      _foundTheGesture();
      return;
    }
    if (pages.length > 1 && at.dx < width / 3) {
      _previous();
      return;
    }
    if (widget.opensPost) showSinglePost(context, widget.post);
  }

  /// The right side was tapped: the hint has done its job, on every card.
  void _foundTheGesture() {
    final hints = ref.read(milestoneHintsProvider);
    hints.markTapped().then((_) {
      if (mounted) ref.invalidate(milestoneHintStateProvider);
    });
  }

  /// Whether the hint is on for this card: a multi-photo post, on the
  /// cover, that the hint belongs on.
  bool _hintOn(MilestoneHintState? state) =>
      _multi && _page == 0 && state != null && state.showFor(widget.post.id);

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
                  child: _TopRow(post: post),
                ),
                Positioned(
                  left: _kInset,
                  right: _kInset,
                  // The actions carry 12 of their own below the words;
                  // the words' line ends 16 from the edge.
                  bottom: _kBottom - PostInteractions.verticalPad,
                  child: _Bottom(
                    post: post,
                    pages: _multi ? pages.length : 1,
                    page: index,
                    hint: hint,
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
  /// scrim and the ring; the surface when there is nothing to show.
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
        final centre = ringCentre(page, post);
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
            Positioned(
              top: milestoneRingTop(size.height),
              left: (size.width - kMilestoneRingSize) / 2,
              child: MilestoneRing(
                onPhoto: true,
                center: MilestoneRingCentre(
                  figure: centre.figure,
                  unit: centre.unit,
                  onPhoto: true,
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _drawnCover() => MilestoneCover(
    photos: [
      for (final p in widget.post.photos)
        if (p.url.isNotEmpty) postImageProvider(p.url),
    ],
    milestoneHours: widget.post.milestoneHours,
  );
}

/// The handle, the way to whoever posted, and how long ago at the right.
class _TopRow extends ConsumerWidget {
  const _TopRow({required this.post});

  final MilestonePost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = post.author;
    final handle = author.username.isNotEmpty ? author.username : author.label;
    final createdAt = post.createdAt;
    return Row(
      children: [
        // The handle takes the line; the time sits at the right inset.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openProfile(
              context,
              ref,
              post.authorUid,
              handle: author.username,
              displayName: author.displayName,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kText,
                ),
              ),
            ),
          ),
        ),
        if (createdAt != null) ...[
          const SizedBox(width: 12),
          IgnorePointer(
            child: Text(
              RelativeTime.of(createdAt),
              style: const TextStyle(fontSize: 13, color: _kTextTime),
            ),
          ),
        ],
      ],
    );
  }
}

/// The task, its caption — or the hint — and, on the actions' line, the
/// page dots at the left and the actions at the right.
class _Bottom extends StatelessWidget {
  const _Bottom({
    required this.post,
    required this.pages,
    required this.page,
    required this.hint,
  });

  final MilestonePost post;
  final int pages;
  final int page;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    final caption = hint ? kMilestoneHintText : post.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          child: Text(
            post.taskName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _kText,
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 3),
          IgnorePointer(
            child: Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: _kTextCaption),
            ),
          ),
        ],
        // Nothing declared: the actions' own 12 above the words is the 12.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pages > 1)
              IgnorePointer(
                child: Padding(
                  // The dots stand on the words' baseline.
                  padding: EdgeInsets.only(
                    top: PostInteractions.wordBaseline(context) - _PageDots.size,
                  ),
                  child: _PageDots(count: pages, current: page),
                ),
              ),
            const Spacer(),
            PostInteractions(post: post, onPhoto: true),
          ],
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  static const double size = 5;
  static const double gap = 4;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == current ? _kText : _kDotOther,
            ),
          ),
        ],
      ],
    );
  }
}
