import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../shared/sondr_action.dart';
import '../../../shared/sondr_field.dart';
import '../../../shared/sondr_swipe_row.dart';
import '../../../core/utils/relative_time.dart';
import '../models/comment.dart';
import '../posts_repository.dart';

/// Opens the comments for [postId] as a draggable bottom sheet.
Future<void> showCommentsSheet(BuildContext context, String postId) {
  final tokens = GreyscaleTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // Background, not surface: the composer's field is a SURFACE capsule, and
    // on a surface-toned sheet it disappeared completely — leaving Post
    // floating beside nothing. The sheet is a page; the capsule sits on it.
    backgroundColor: tokens.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CommentsSheet(postId: postId),
  );
}

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final repo = ref.read(postsRepositoryProvider);
    if (text.isEmpty || repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await repo.addComment(widget.postId, text);
      _input.clear();
    } on FirebaseException catch (e) {
      debugPrint('SONDR comment error: ${e.code} :: ${e.message}');
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Couldn’t post comment.')));
    } catch (e) {
      debugPrint('SONDR comment error: $e');
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Couldn’t post comment.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String commentId) async {
    final repo = ref.read(postsRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.deleteComment(widget.postId, commentId);
    } catch (_) {/* ignore — the stream stays as-is on failure */}
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final comments = ref.watch(postCommentsProvider(widget.postId));

    return Padding(
      // Lift above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              // One rhythm down the head of the sheet: grabber, title, list
              // are all a base unit apart. The three hand-picked gaps that
              // were here (10 / 12 / 8) were what made it read unsettled.
              SizedBox(height: kSpacingBase * scale),
              Container(
                width: 36 * scale,
                height: 4 * scale,
                decoration: BoxDecoration(
                  color: tokens.ringTrack,
                  borderRadius: BorderRadius.circular(2 * scale),
                ),
              ),
              SizedBox(height: kSpacingBase * scale),
              Text(
                'Comments',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              SizedBox(height: kSpacingBase * scale),
              Expanded(
                child: comments.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: Text('Couldn’t load comments.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: tokens.textSecondary)),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
                        child: Text('No comments yet. Say something kind.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: tokens.textSecondary)),
                      );
                    }
                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final tile = _CommentTile(comment: c);
                        // Your own comment hides its Delete behind a swipe,
                        // exactly as a friend row hides Remove and Block. An
                        // affordance sitting on every one of your comments is
                        // clutter on the common case.
                        if (c.authorUid != uid) return tile;
                        return SondrSwipeRow(
                          actions: [
                            SondrAction(
                              label: 'Delete',
                              onPressed: () => _delete(c.id),
                            ),
                          ],
                          child: tile,
                        );
                      },
                    );
                  },
                ),
              ),
              // No divider: the sheet's own edge and the spacing separate
              // the composer from the list.
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24 * scale,
                  kSpacingBase * scale,
                  24 * scale,
                  kSpacingBase * scale,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SondrField(
                        controller: _input,
                        enabled: !_busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _busy ? null : _send(),
                      ),
                    ),
                    SizedBox(width: kSpacingPair * scale),
                    // Text, not a paper plane. Full weight: it is the one
                    // action in the sheet, and grey-on-grey beside the field
                    // read as disabled.
                    SondrAction(
                      label: 'Post',
                      onPressed: _busy ? null : _send,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final theme = Theme.of(context);
    final initial = comment.author.label.isNotEmpty
        ? comment.author.label[0].toUpperCase()
        : '?';

    return Padding(
      // The row carries the app's 24 gutter itself so the swipe tray can open
      // into it, rather than the list insetting every row by 20.
      padding: EdgeInsets.symmetric(
        horizontal: 24 * scale,
        vertical: kSpacingPair * scale,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: kAvatarComment / 2 * scale,
            // Surface on a background-toned sheet, the same way a friend row
            // draws its placeholder — background-on-background left the
            // initial floating with no disc behind it.
            backgroundColor: tokens.surface,
            child: Text(
              initial,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textSecondary,
              ),
            ),
          ),
          SizedBox(width: kSpacingBase * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.author.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    SizedBox(width: kSpacingPair * scale),
                    if (comment.createdAt != null)
                      Text(
                        RelativeTime.of(comment.createdAt!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w700,
                          color: tokens.textTertiary,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: kSpacingPair * scale),
                Text(
                  comment.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
