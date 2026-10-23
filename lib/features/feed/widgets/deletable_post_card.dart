import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../shared/sondr_action.dart';
import '../../../shared/sondr_error.dart';
import '../../../shared/sondr_notice.dart';
import '../../reports/report.dart';
import '../../reports/report_flow.dart';
import '../models/post.dart';
import '../posts_repository.dart';

/// The post id whose delete overlay is currently revealed (null = none). A
/// provider so only ONE card is revealed at a time — long-pressing another card
/// moves the reveal to it.
class RevealedPostId extends Notifier<String?> {
  @override
  String? build() => null;

  void reveal(String id) => state = id;
  void clear() => state = null;
}

final revealedPostIdProvider = NotifierProvider<RevealedPostId, String?>(
  RevealedPostId.new,
);

/// Wraps a feed [child] card with a long-press: Delete on the author's
/// **own** posts, Report on everybody else's. Long-press → blur THIS card
/// and reveal the action and Close. Delete un-shares via
/// [PostsRepository.deletePost] (the post doc + its posts-space photo copies —
/// never the gallery original or logged time); the feed stream then drops the
/// card. Close, or a tap on the blurred scrim, un-blurs. No confirm dialog — the
/// long-press plus a deliberate tap is the confirmation.
class DeletablePostCard extends ConsumerStatefulWidget {
  const DeletablePostCard({
    super.key,
    required this.post,
    required this.child,
    this.onDelete,
  });

  final Post post;
  final Widget child;

  /// Test seam. Defaults to `postsRepository.deletePost`; production passes none.
  final Future<void> Function(Post)? onDelete;

  @override
  ConsumerState<DeletablePostCard> createState() => _DeletablePostCardState();
}

class _DeletablePostCardState extends ConsumerState<DeletablePostCard> {
  bool _busy = false;
  String? _error;

  /// Set once the report is in. The overlay stays, carrying the thank-you,
  /// and the card itself leaves when the hidden set catches up — so the
  /// promise is read rather than inferred from a card vanishing.
  bool _thanked = false;

  /// Match the wrapped card's corner radius so the blur clips to its shape.
  double get _radius => widget.post is SessionPost ? 16 : 24;

  void _clear() => ref.read(revealedPostIdProvider.notifier).clear();

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      final del =
          widget.onDelete ??
          (Post p) async {
            final repo = ref.read(postsRepositoryProvider);
            if (repo == null) throw StateError('not signed in');
            await repo.deletePost(p);
          };
      await del(widget.post);
      // Success: the feed stream drops this post and the widget unmounts. Clear
      // the revealed id (and un-busy) if we're somehow still mounted.
      if (mounted) {
        setState(() => _busy = false);
        _clear();
      }
    } catch (e) {
      debugPrint('SONDR delete post error: $e');
      if (mounted) {
        // Stay open on failure: the overlay is where the action was, and
        // closing it would take the message with it.
        setState(() {
          _busy = false;
          _error = 'Couldn’t delete the post. Please try again.';
        });
      }
    }
  }

  /// Whose post this is, which decides what the long-press offers.
  bool _own = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    _own = uid != null && widget.post.authorUid == uid;
    final revealed = ref.watch(revealedPostIdProvider) == widget.post.id;

    return GestureDetector(
      // Opaque so the long-press is caught across the whole card, including any
      // transparent regions; the card's own taps (like/comment) still win.
      behavior: HitTestBehavior.opaque,
      // Every post answers a long-press now; what it offers depends on
      // whose it is.
      onLongPress: () =>
          ref.read(revealedPostIdProvider.notifier).reveal(widget.post.id),
      child: Stack(
        children: [
          widget.child,
          if (revealed) Positioned.fill(child: _overlay(context)),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: GestureDetector(
          // Tap the scrim (outside the buttons) to close.
          onTap: _busy ? null : _clear,
          child: Container(
            color: Colors.black.withValues(alpha: 0.4),
            // Tight: a slim session card has barely room for two stacked
            // actions, and the actions carry their own tap padding already.
            padding: EdgeInsets.all(kSpacingPair * figmaScale(context)),
            // Centred when it fits, scrolling when it does not. A session
            // card is 80 tall and two stacked actions nearly fill it, so a
            // line of words on top of them — "couldn't send that report",
            // the thank-you — overflowed by 13 and clipped the way out.
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  // The actions STAY while the delete runs — only the label
                  // and the tone move, so the overlay does not jump.
                  child: Center(child: _actions(tokens)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Report someone else's post: ask why, send, and let the feed drop it.
  Future<void> _report() async {
    setState(() => _busy = true);
    final outcome = await reportThing(
      context,
      ref,
      type: ReportTarget.post,
      targetKey: widget.post.id,
      targetOwnerUid: widget.post.authorUid,
      title: reportTitle(ReportTarget.post),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case ReportOutcome.cancelled:
        break;
      case ReportOutcome.sent:
        // The card goes with the hidden set, and takes the overlay with
        // it. Until then the thank-you is what the overlay says.
        setState(() => _thanked = true);
      case ReportOutcome.failed:
        // Stay open, say so, hide nothing.
        setState(() => _error = kReportFailed);
    }
  }

  Widget _actions(GreyscaleTokens tokens) {
    // Delete is summoned by the long-press, so it stays at full emphasis:
    // plain white text, no fill, no border, no glyph (see DESIGN.md). Close
    // is the exit and takes the supporting tone, stacked beneath rather than
    // beside so the two never read as a pair of equals.
    if (_thanked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SondrNotice(kReportThanks, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          SondrAction(label: 'Close', supporting: true, onPressed: _clear),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          SondrError(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
        ],
        if (_own)
          SondrAction(
            label: _busy ? 'Deleting…' : 'Delete',
            onPressed: _busy ? null : _delete,
          )
        else
          SondrAction(label: 'Report', onPressed: _busy ? null : _report),
        SondrAction(
          label: 'Close',
          supporting: true,
          onPressed: _busy ? null : _clear,
        ),
      ],
    );
  }
}
