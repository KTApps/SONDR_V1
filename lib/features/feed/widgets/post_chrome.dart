import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/utils/relative_time.dart';
import '../models/post.dart';

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

/// Like + comment affordances with counts. Static for now — the interaction
/// backend (likes/comments) is a later step.
class PostInteractions extends StatelessWidget {
  const PostInteractions({
    super.key,
    this.likes = 0,
    this.comments = 0,
    this.onPhoto = false,
  });

  final int likes;
  final int comments;
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final color = onPhoto ? Colors.white : tokens.textSecondary;
    final shadows = onPhoto ? kTextShadows : null;

    Widget item(IconData icon, int count) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color, shadows: shadows),
            const SizedBox(width: 6),
            Text('$count',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: color, shadows: shadows)),
          ],
        );

    return Row(
      children: [
        item(Icons.favorite_border, likes),
        const SizedBox(width: 20),
        item(Icons.mode_comment_outlined, comments),
      ],
    );
  }
}
