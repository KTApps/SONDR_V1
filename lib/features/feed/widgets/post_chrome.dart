import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../core/utils/relative_time.dart';
import '../../../shared/cached_photo.dart';
import '../../../shared/sondr_error.dart';
import '../../profile/other_profile_screen.dart';
import '../models/post.dart';
import '../posts_repository.dart';
import 'comments_sheet.dart';
import 'likes_sheet.dart';

/// Soft dark halo behind text that sits over a photo (spec technique #3), so
/// captions/usernames stay legible on bright images.
const List<Shadow> kTextShadows = [
  Shadow(blurRadius: 6, color: Colors.black87, offset: Offset(0, 1)),
];

/// Bundled asset (mock feed) vs cached network (real Storage URL). The network
/// branch goes through the shared cache so a milestone photo isn't re-fetched on
/// every feed rebuild.
ImageProvider postImageProvider(String url) {
  if (url.startsWith('assets/')) return AssetImage(url);
  // A photo not yet uploaded — the new shot, on the final look before the
  // share — stands in as the file it was written to.
  if (url.startsWith('file://')) return FileImage(File(Uri.parse(url).toFilePath()));
  return cachedPhotoProvider(url);
}

/// Author avatar + name + relative time. [onPhoto] flips to light text with
/// shadows for the photo-backdrop card.
///
/// The avatar and the name are the way to that person's profile — which is
/// why the row carries [authorUid] and not only the denormalised name it
/// prints. The timestamp is not part of the tap target: it is information
/// about the post, not about the person.
class PostAuthorRow extends ConsumerWidget {
  const PostAuthorRow({
    super.key,
    required this.author,
    required this.authorUid,
    required this.createdAt,
    this.onPhoto = false,
  });

  final PostAuthor author;

  /// Whose post it is. Their profile; mine switches to the Profile tab.
  final String authorUid;
  final DateTime? createdAt;
  final bool onPhoto;

  /// Their profile, told what this row already prints — so a profile whose
  /// owner has published nothing still opens with a name in it.
  void _open(BuildContext context, WidgetRef ref) => openProfile(
    context,
    ref,
    authorUid,
    handle: author.username,
    displayName: author.displayName,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context, ref),
          child: Row(
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
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(context, ref),
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

  /// The tap target above and below each word, on the reference canvas.
  static const double verticalPad = kSpacingBase;

  /// The words' style in [context] — one place, so a layout that has to
  /// line something up with them measures the same text they draw.
  static TextStyle? wordStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 15 * figmaScale(context),
        fontWeight: FontWeight.w700,
      );

  /// How far below the row's top the words' baseline lies: the padding,
  /// then the text's own ascent at the user's text size. For the milestone
  /// card's page dots, which stand on that line.
  static double wordBaseline(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Like', style: wordStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.dispose();
    return verticalPad * figmaScale(context) + baseline;
  }

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
            padding: EdgeInsets.symmetric(
              vertical: PostInteractions.verticalPad * scale,
            ),
            child: Text(
              label,
              style: PostInteractions.wordStyle(context)?.copyWith(
                color: labelColor,
                shadows: shadows,
              ),
            ),
          ),
        );

    // An author cannot like their own post; the word there is "Likes",
    // which opens who did.
    final mine = post.authorUid == ref.watch(currentUidProvider);
    final row = Row(
      children: [
        if (mine)
          action(
            label: 'Likes',
            onTap: () => showLikesSheet(context, post.id),
          )
        else
        action(
          label: liked ? 'Liked' : 'Like',
          onTap: repo == null
              ? null
              : () async {
                  try {
                    await repo.setLike(post.id, !liked, authorUid: post.authorUid);
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
