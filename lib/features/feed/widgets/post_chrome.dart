import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../core/utils/relative_time.dart';
import '../../../shared/cached_photo.dart';
import '../../../shared/sondr_error.dart';
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

/// Like + comments row. Two words, no figures: "Like" toggles (and becomes
/// "Liked"), "Comments" opens the sheet.
class PostInteractions extends ConsumerStatefulWidget {
  const PostInteractions({super.key, required this.post, this.onPhoto = false});

  final Post post;
  final bool onPhoto;

  @override
  ConsumerState<PostInteractions> createState() => _PostInteractionsState();
}

class _PostInteractionsState extends ConsumerState<PostInteractions> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final onPhoto = widget.onPhoto;
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final labelColor = onPhoto ? kOnPhoto : tokens.textPrimary;
    final shadows = onPhoto ? kTextShadows : null;

    final liked = ref
        .watch(myLikedPostsProvider)
        .maybeWhen(data: (ids) => ids.contains(post.id), orElse: () => false);
    final repo = ref.read(postsRepositoryProvider);

    // Text, never a glyph — and no figures either. The counts are gone: a
    // post's worth is not a number on it, and "4" beside Like invited reading
    // the feed as a scoreboard. The word alone carries the action, and the
    // Like state is carried by the WORD — "Like" before, "Liked" after. Both
    // labels are the full-emphasis action style (15/bold/textPrimary), the
    // same as every SondrAction: with the figures gone there is nothing left
    // for a dimmer tone to separate them from.
    Widget action({required String label, required VoidCallback? onTap}) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: kSpacingBase * scale),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15 * scale,
                fontWeight: FontWeight.w700,
                color: labelColor,
                shadows: shadows,
              ),
            ),
          ),
        );

    final row = Row(
      children: [
        action(
          label: liked ? 'Liked' : 'Like',
          onTap: repo == null
              ? null
              : () async {
                  try {
                    await repo.setLike(post.id, !liked);
                    if (mounted && _error != null) {
                      setState(() => _error = null);
                    }
                  } on FirebaseException catch (e) {
                    debugPrint('SONDR like error: ${e.code} :: ${e.message}');
                    if (mounted) {
                      setState(() => _error = 'Couldn’t update like.');
                    }
                  } catch (e) {
                    debugPrint('SONDR like error: $e');
                  }
                },
        ),
        SizedBox(width: kSpacingSection * scale),
        action(
          label: 'Comments',
          onTap: () => showCommentsSheet(context, post.id),
        ),
      ],
    );

    if (_error == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        // Under the action that failed, inside the card — a SnackBar put it
        // at the bottom of the screen, nowhere near the post it was about.
        SondrError(_error!),
      ],
    );
  }
}
