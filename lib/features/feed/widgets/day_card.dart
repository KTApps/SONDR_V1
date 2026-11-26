import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../photos/capture_crop.dart';
import '../models/post.dart';
import 'deletable_post_card.dart';
import 'session_card.dart';

/// One person's last day, as one card: a single photo at the card's full
/// width, or several in a row that swipes a page at a time with the next
/// peeking in. Each page is a session card of its own — its photo,
/// caption, Like and Comments and small ring — and a long-press on one
/// is about that post alone.

/// The feed's side margin, which a lone card and the first page sit on.
const double kDayCardMargin = 16;

/// A page's width is the screen's less this: 340 on a 390 screen.
const double kDayPageInset = 50;

/// Between two pages.
const double kDayPageGap = 8;

/// The pages of a day, for the pager: which post is on which page. Pure,
/// so the order and the anchoring are tested without a widget.
List<String> dayPageIds(List<SessionPost> posts) => [for (final p in posts) p.id];

/// Where a page should be after the day changed: the page of the post that
/// was showing, if it is still there; else the nearest page to where it was.
int anchoredPage(List<String> before, int page, List<String> after) {
  if (after.isEmpty) return 0;
  if (page >= 0 && page < before.length) {
    final at = after.indexOf(before[page]);
    if (at >= 0) return at;
  }
  return math.min(math.max(page, 0), after.length - 1);
}

class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.posts});

  /// Newest first.
  final List<SessionPost> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.length == 1) {
      final post = posts.single;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: kDayCardMargin),
        child: DeletablePostCard(
          key: ValueKey('page-${post.id}'),
          post: post,
          child: SessionCard(post: post),
        ),
      );
    }
    return DayPager(posts: posts);
  }
}

/// Several photos: a row of pages that snaps one at a time.
class DayPager extends StatefulWidget {
  const DayPager({super.key, required this.posts});

  final List<SessionPost> posts;

  @override
  State<DayPager> createState() => _DayPagerState();
}

class _DayPagerState extends State<DayPager> {
  final ScrollController _row = ScrollController();

  /// The page a drag began on, so a fling goes one page from there.
  final _DragStart _start = _DragStart();
  late List<String> _ids = dayPageIds(widget.posts);

  /// The page showing — the post it shows is what is kept in place when
  /// another arrives.
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _row.addListener(_onScroll);
  }

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  double get _stride =>
      MediaQuery.sizeOf(context).width - kDayPageInset + kDayPageGap;

  void _onScroll() {
    if (!_row.hasClients) return;
    final p = _row.position;
    final page = p.pixels >= p.maxScrollExtent - 0.5 && p.maxScrollExtent > 0
        ? _ids.length - 1
        : (p.pixels / _stride).round().clamp(0, _ids.length - 1);
    _page = page;
  }

  @override
  void didUpdateWidget(DayPager old) {
    super.didUpdateWidget(old);
    final next = dayPageIds(widget.posts);
    if (listEquals(next, _ids)) return;
    final page = anchoredPage(_ids, _page, next);
    _ids = next;
    _page = page;
    // A new photo lands first in the row; the one being looked at stays
    // in front of the eyes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_row.hasClients) return;
      _row.jumpTo(math.min(page * _stride, _row.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - kDayPageInset;
    return SizedBox(
      height: width / kCaptureAspect,
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (n) {
          if (n.dragDetails != null) {
            _start.page = (n.metrics.pixels / _stride).round();
          }
          return false;
        },
        child: SingleChildScrollView(
        key: kDayPagerKey,
        controller: _row,
        scrollDirection: Axis.horizontal,
        physics: _PageSnap(
          stride: _stride,
          start: _start,
          parent: const ClampingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: kDayCardMargin),
        child: Row(
          children: [
            for (var i = 0; i < widget.posts.length; i++) ...[
              if (i > 0) const SizedBox(width: kDayPageGap),
              SizedBox(
                width: width,
                child: DeletablePostCard(
                  key: ValueKey('page-${widget.posts[i].id}'),
                  post: widget.posts[i],
                  child: SessionCard(post: widget.posts[i]),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// Where the current drag began, shared with the physics.
class _DragStart {
  int page = 0;
}

const Key kDayPagerKey = ValueKey('day-pager');

/// Snaps to a page at a time: wherever a fling or a drag would have left
/// the row, it settles on the nearest page in the direction it was going,
/// and never more than one page on. The last page settles at the row's end.
class _PageSnap extends ScrollPhysics {
  const _PageSnap({required this.stride, required this.start, super.parent});

  final double stride;
  final _DragStart start;

  @override
  _PageSnap applyTo(ScrollPhysics? ancestor) =>
      _PageSnap(stride: stride, start: start, parent: buildParent(ancestor));

  double _target(ScrollMetrics position, double velocity) {
    final from = start.page;
    var page = (position.pixels / stride).round();
    if (velocity > 200) {
      page = from + 1;
    } else if (velocity < -200) {
      page = from - 1;
    }
    // One page on at most from where the drag began.
    page = page.clamp(from - 1, from + 1);
    return (page * stride).clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = _target(position, velocity);
    if ((target - position.pixels).abs() < 0.5) return null;
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1.1),
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
