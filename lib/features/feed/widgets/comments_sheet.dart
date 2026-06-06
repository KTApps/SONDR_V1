import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/relative_time.dart';
import '../models/comment.dart';
import '../posts_repository.dart';

/// Opens the comments for [postId] as a draggable bottom sheet.
Future<void> showCommentsSheet(BuildContext context, String postId) {
  final tokens = GreyscaleTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: tokens.surface,
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
      // TEMP diagnostic: surface the real Firebase code on-screen.
      debugPrint('SONDR comment error: ${e.code} :: ${e.message}');
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Comment failed: ${e.code}')));
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
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.ringTrack,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text('Comments', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
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
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _CommentTile(
                        comment: list[i],
                        isMine: list[i].authorUid == uid,
                        onDelete: () => _delete(list[i].id),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !_busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _busy ? null : _send(),
                        decoration: const InputDecoration(
                          hintText: 'Add a comment…',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _send,
                      icon: Icon(Icons.send, color: tokens.textPrimary),
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
  const _CommentTile({
    required this.comment,
    required this.isMine,
    required this.onDelete,
  });

  final Comment comment;
  final bool isMine;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final initial = comment.author.label.isNotEmpty
        ? comment.author.label[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: tokens.background,
            child: Text(initial,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: tokens.textSecondary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.author.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: tokens.textPrimary)),
                    const SizedBox(width: 8),
                    if (comment.createdAt != null)
                      Text(RelativeTime.of(comment.createdAt!),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: tokens.textTertiary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: tokens.textSecondary)),
              ],
            ),
          ),
          if (isMine)
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.delete_outline,
                    size: 18, color: tokens.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}
