import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
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

/// Wraps a feed [child] card with long-press-to-delete on the author's **own**
/// posts only. Long-press an own post → blur THIS card and reveal Delete / Close;
/// long-press someone else's post → nothing. Delete un-shares via
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

  /// A slim post (session, no photo) has no vertical room → buttons side by side.
  /// Every other card is tall → Delete stacked above Close.
  bool get _isSlim => widget.post is SessionPost && widget.post.photos.isEmpty;

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
        setState(() => _busy = false);
        _clear();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Couldn’t delete the post. Please try again.'),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final own = uid != null && widget.post.authorUid == uid;
    final revealed = ref.watch(revealedPostIdProvider) == widget.post.id;

    return GestureDetector(
      // Opaque so the long-press is caught across the whole card, including any
      // transparent regions; the card's own taps (like/comment) still win.
      behavior: HitTestBehavior.opaque,
      onLongPress: own
          ? () =>
                ref.read(revealedPostIdProvider.notifier).reveal(widget.post.id)
          : null,
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
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _actions(tokens),
          ),
        ),
      ),
    );
  }

  Widget _actions(GreyscaleTokens tokens) {
    final delete = ElevatedButton.icon(
      onPressed: _delete,
      icon: const Icon(Icons.delete_outline, size: 18),
      label: const Text('Delete'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    final close = TextButton(
      onPressed: _clear,
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      child: const Text('Close'),
    );

    if (_isSlim) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [delete, const SizedBox(width: 16), close],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [delete, const SizedBox(height: 20), close],
    );
  }
}
