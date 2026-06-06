import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/relative_time.dart';
import '../models/post.dart';
import '../posts_repository.dart';
import 'comments_sheet.dart';

/// Soft dark halo behind text that sits over a photo (spec technique #3), so
/// captions/usernames stay legible on bright images.
const List<Shadow> kTextShadows = [
  Shadow(blurRadius: 6, color: Colors.black87, offset: Offset(0, 1)),
];

/// Bundled asset (mock feed) vs network (real Storage URL).
ImageProvider postImageProvider(String url) =>
    url.startsWith('assets/') ? AssetImage(url) : NetworkImage(url);

/// Author avatar + name + relative time. [onPhoto] flips to light text with
/// shadows for the photo-backdrop card.
class PostAuthorRow extends StatelessWidget {
  const PostAuthorRow({
    super.key,
    required this.author,
    required this.createdAt,
    this.onPhoto = false,
  });

  final PostAuthor author;
  final DateTime? createdAt;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final primary = onPhoto ? Colors.white : tokens.textPrimary;
    final secondary = onPhoto ? Colors.white70 : tokens.textTertiary;
    final shadows = onPhoto ? kTextShadows : null;
    final initial =
        author.label.isNotEmpty ? author.label[0].toUpperCase() : '?';

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: onPhoto ? Colors.white24 : tokens.background,
          child: Text(initial,
              style: theme.textTheme.labelLarge?.copyWith(color: primary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            author.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: primary, shadows: shadows),
          ),
        ),
        if (createdAt != null)
          Text(
            RelativeTime.of(createdAt!),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: secondary, shadows: shadows),
          ),
      ],
    );
  }
}

/// Like + comment row. The heart reflects the post's likeCount and whether this
/// user has liked it (tap toggles); the comment icon shows commentCount and
/// opens the comments sheet.
class PostInteractions extends ConsumerWidget {
  const PostInteractions({super.key, required this.post, this.onPhoto = false});

  final Post post;
  final bool onPhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final color = onPhoto ? Colors.white : tokens.textSecondary;
    final activeColor = onPhoto ? Colors.white : tokens.textPrimary;
    final shadows = onPhoto ? kTextShadows : null;

    final liked = ref.watch(myLikedPostsProvider).maybeWhen(
          data: (ids) => ids.contains(post.id),
          orElse: () => false,
        );
    final repo = ref.read(postsRepositoryProvider);

    Widget item({
      required IconData icon,
      required int count,
      required Color iconColor,
      required VoidCallback? onTap,
    }) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: iconColor, shadows: shadows),
                const SizedBox(width: 6),
                Text('$count',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: color, shadows: shadows)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        item(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          count: post.likeCount,
          iconColor: liked ? activeColor : color,
          onTap: repo == null
              ? null
              : () async {
                  // TEMP diagnostic: surface the real Firebase code on-screen.
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await repo.setLike(post.id, !liked);
                  } on FirebaseException catch (e) {
                    debugPrint('SONDR like error: ${e.code} :: ${e.message}');
                    messenger
                      ..clearSnackBars()
                      ..showSnackBar(
                          SnackBar(content: Text('Like failed: ${e.code}')));
                  } catch (e) {
                    debugPrint('SONDR like error: $e');
                  }
                },
        ),
        const SizedBox(width: 16),
        item(
          icon: Icons.mode_comment_outlined,
          count: post.commentCount,
          iconColor: color,
          onTap: () => showCommentsSheet(context, post.id),
        ),
      ],
    );
  }
}
