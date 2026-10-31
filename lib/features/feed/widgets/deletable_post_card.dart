import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../reports/report.dart';
import '../../../core/debug_tools.dart';
import '../../../core/theme/spacing.dart';
import '../../../shared/blur_sheet.dart';
import '../../../shared/sondr_error.dart';
import '../../reports/report_flow.dart';
import '../models/post.dart';
import '../share_progress.dart';
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
/// What the question says when the deleting failed. A card still
/// standing was taken as the message, and it is not one: a post that
/// refuses to go looks exactly like a tap that missed.
const String kDeleteFailed = 'Couldn’t delete. Try again.';

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

  /// Ask, and stay open to say so if it does not work. The line clears
  /// the moment they try again.
  Future<void> _confirmDelete() async {
    String? failure;
    await showBlurSheet(context, (handle) {
      BlurView question() => BlurView(
        title: kDeletePostTitle,
        explanation: kDeletePostBody,
        // Above the answers, in the app's one error style.
        body: failure == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: kSpacingBase),
                child: SondrError(failure!, textAlign: TextAlign.center),
              ),
        items: [
          BlurItem(
            label: 'Delete',
            onTap: () async {
              failure = null;
              if (mounted) handle.show(question());
              final said = await _delete();
              if (said == null) {
                handle.close();
                return;
              }
              failure = said;
              if (mounted) handle.show(question());
            },
          ),
        ],
      );
      return question();
    });
  }

  /// Deletes, and returns the line to show when it did not work.
  Future<String?> _delete() async {
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
      // Said on the Feed, wherever this was done from.
      ref.read(postDeletedProvider.notifier).say();
      // Success: the feed stream drops this post and the widget unmounts.
      if (mounted) setState(() => _busy = false);
      return null;
    } catch (e) {
      debugPrint('SONDR delete post error: $e');
      if (mounted) setState(() => _busy = false);
      final code = e is FirebaseException ? e.code : '${e.runtimeType}';
      return ref.read(debugToolsProvider)
          ? '$kDeleteFailed ($code)'
          : kDeleteFailed;
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
