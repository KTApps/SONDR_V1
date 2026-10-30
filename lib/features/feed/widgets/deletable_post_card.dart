import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../shared/sondr_prompt.dart';
import '../../reports/report.dart';
import '../../reports/report_flow.dart';
import '../models/post.dart';
import '../posts_repository.dart';

/// A feed card that answers a long-press.
///
/// Your own post asks whether to delete it; somebody else's goes straight
/// to the reasons for reporting it — a list of two answers to choose
/// between "report" and nothing was a step that answered itself.
///
/// The question is the app's frosted view rather than a panel over the
/// card. A card-sized overlay could not hold a sentence without
/// overflowing a slim session card, and an answer to "delete this?"
/// should not land where the finger that asked it was.
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

  /// What the question says. Truthful about what deleting actually
  /// reaches: the post and the copies of its photos that went out with
  /// it, and nothing in the gallery or the hours.
  static const String kDeletePostTitle = 'Delete this post?';
  static const String kDeletePostBody =
      'It will be removed from your friends\' feeds. Your photos and your '
      "logged time stay. This can't be undone.";

  Future<void> _confirmDelete() async {
    final yes = await showSondrConfirm(
      context,
      title: kDeletePostTitle,
      body: kDeletePostBody,
      confirmLabel: 'Delete',
    );
    if (yes && mounted) await _delete();
  }

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
      // Success: the feed stream drops this post and the widget unmounts.
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      debugPrint('SONDR delete post error: $e');
      // There is no panel to hold a line any more, and a card that is
      // still there IS the message: the post did not go.
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whose post this is, which decides what the long-press offers.
  bool _own = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    _own = uid != null && widget.post.authorUid == uid;

    return GestureDetector(
      // Opaque so the long-press is caught across the whole card, including
      // any transparent regions; the card's own taps (like/comment) still
      // win.
      behavior: HitTestBehavior.opaque,
      // Every post answers a long-press; what it asks depends on whose it
      // is. The question is the frosted view the whole app asks on now,
      // not a panel over the card: a card-sized overlay could not hold a
      // sentence without overflowing a slim session card, and the answer
      // to "delete this?" belongs nowhere near the thing it is about.
      onLongPress: _busy || uid == null
          ? null
          : () {
              // Felt as the press is recognised, before the sheet moves:
              // a menu is opening.
              HapticFeedback.mediumImpact();
              (_own ? _confirmDelete : _report)();
            },
      child: widget.child,
    );
  }

  /// Report someone else's post: ask why, send, and let the feed drop it.
  /// Straight to the reasons: a long-press on somebody else's post has
  /// one thing it can mean, and a list of two answers to say it with was
  /// a step that answered itself.
  Future<void> _report() async {
    setState(() => _busy = true);
    await reportThing(
      context,
      ref,
      type: ReportTarget.post,
      targetKey: widget.post.id,
      targetOwnerUid: widget.post.authorUid,
      title: reportTitle(ReportTarget.post),
    );
    if (mounted) setState(() => _busy = false);
  }


}
