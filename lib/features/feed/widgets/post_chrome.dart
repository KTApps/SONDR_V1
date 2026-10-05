import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../core/utils/relative_time.dart';
import '../../../shared/cached_photo.dart';
import '../models/post.dart';
import '../posts_repository.dart';
import 'comments_sheet.dart';

/// Soft dark halo behind text that sits over a photo (spec technique #3), so
/// captions/usernames stay legible on bright images.
const List<Shadow> kTextShadows = [
  Shadow(blurRadius: 6, color: Colors.black87, offset: Offset(0, 1)),
];

/// Bundled asset (mock feed) vs cached network (real Storage URL). The network
/// branch goes through the shared cache so a milestone photo isn't re-fetched on
/// every feed rebuild.
ImageProvider postImageProvider(String url) =>
    url.startsWith('assets/') ? AssetImage(url) : cachedPhotoProvider(url);

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
    final scale = figmaScale(context);
    final primary = onPhoto ? kOnPhoto : tokens.textPrimary;
    final secondary = onPhoto ? kOnPhotoDim : tokens.textTertiary;
    final shadows = onPhoto ? kTextShadows : null;
    final initial = author.label.isNotEmpty
        ? author.label[0].toUpperCase()
        : '?';

    return Row(
      children: [
        CircleAvatar(
          radius: kAvatarPost / 2 * scale,
          backgroundColor: onPhoto ? kOnPhotoFill : tokens.background,
          child: Text(
            initial,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13 * scale,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
        ),
        SizedBox(width: kSpacingBase * scale),
        Expanded(
          child: Text(
            author.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w700,
              color: primary,
              shadows: shadows,
            ),
          ),
        ),
        if (createdAt != null)
          Text(
            RelativeTime.of(createdAt!),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w700,
              color: secondary,
              shadows: shadows,
            ),
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
    final scale = figmaScale(context);
    final color = onPhoto ? kOnPhotoDim : tokens.textSecondary;
    final activeColor = onPhoto ? kOnPhoto : tokens.textPrimary;
    final countColor = onPhoto ? kOnPhotoDim : tokens.textTertiary;
    final shadows = onPhoto ? kTextShadows : null;

    final liked = ref
        .watch(myLikedPostsProvider)
        .maybeWhen(data: (ids) => ids.contains(post.id), orElse: () => false);
    final repo = ref.read(postsRepositoryProvider);

    // Text, never a glyph. The word carries the action and the count sits
    // beside it as metadata; the Like state is told by TONE ALONE — "Like"
    // grey, "Liked" white. The weight stays bold in both states: letting the
    // weight move too made the unliked word read as a different, lesser kind
    // of control rather than the same one in another state.
    Widget action({
      required String label,
      required int count,
      required bool active,
      required VoidCallback? onTap,
    }) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: kSpacingBase * scale),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                // The app's action size — the same 15/bold as the Friends
                // heading and every SondrAction.
                fontSize: 15 * scale,
                fontWeight: FontWeight.w700,
                color: active ? activeColor : color,
                shadows: shadows,
              ),
            ),
            // A zero count says nothing worth the space.
            if (count > 0) ...[
              SizedBox(width: kSpacingPair * scale),
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: countColor,
                  shadows: shadows,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Row(
      children: [
        action(
          label: liked ? 'Liked' : 'Like',
          count: post.likeCount,
          active: liked,
          onTap: repo == null
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await repo.setLike(post.id, !liked);
                  } on FirebaseException catch (e) {
                    debugPrint('SONDR like error: ${e.code} :: ${e.message}');
                    messenger
                      ..clearSnackBars()
                      ..showSnackBar(
                        const SnackBar(content: Text('Couldn’t update like.')),
                      );
                  } catch (e) {
                    debugPrint('SONDR like error: $e');
                  }
                },
        ),
        SizedBox(width: kSpacingSection * scale),
        action(
          label: 'Comment',
          count: post.commentCount,
          active: true,
          onTap: () => showCommentsSheet(context, post.id),
        ),
      ],
    );
  }
}
