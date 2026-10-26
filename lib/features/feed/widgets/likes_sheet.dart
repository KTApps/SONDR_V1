import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../core/utils/relative_time.dart';
import '../../profile/other_profile_screen.dart';
import '../../profile/public_profile.dart';
import '../posts_repository.dart';

/// Who liked a post. Opened from the word "Likes" on the author's own post.
///
/// Built with the comments sheet's opener — the same height, corner and
/// tone — and its rows are the comment row without the body line, so the
/// two sheets read as one thing.
Future<void> showLikesSheet(BuildContext context, String postId) {
  final tokens = GreyscaleTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    backgroundColor: tokens.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => LikesSheet(postId: postId),
  );
}

/// Who liked [postId], newest first. Null while the first answer is on
/// its way.
final postLikesProvider = StreamProvider.autoDispose
    .family<List<PostLike>, String>((ref, postId) {
      final repo = ref.watch(postsRepositoryProvider);
      if (repo == null) return const Stream.empty();
      return repo.watchLikes(postId);
    });

class LikesSheet extends ConsumerWidget {
  const LikesSheet({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final likes = ref.watch(postLikesProvider(postId));

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: kSpacingBase * scale),
          Center(
            child: Container(
              width: 36 * scale,
              height: 4 * scale,
              decoration: BoxDecoration(
                color: tokens.ringTrack,
                borderRadius: BorderRadius.circular(2 * scale),
              ),
            ),
          ),
          SizedBox(height: kSpacingBase * scale),
          Center(
            child: Text(
              'Likes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 15 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
          SizedBox(height: kSpacingPair * scale),
          Expanded(
            child: likes.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => _quiet(context, 'Couldn’t load likes.'),
              data: (list) => list.isEmpty
                  ? _quiet(context, 'No likes yet')
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: list.length,
                      itemBuilder: (_, i) => _LikeRow(like: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The sheet's quiet line: a sentence, the supporting grey, centred.
  Widget _quiet(BuildContext context, String text) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return Padding(
      padding: EdgeInsets.only(top: kSpacingSection * scale),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13 * scale,
          color: tokens.textTertiary,
        ),
      ),
    );
  }
}

/// The comment row without its body line: the avatar, the name, when.
class _LikeRow extends ConsumerWidget {
  const _LikeRow({required this.like});

  final PostLike like;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final profile = ref.watch(publicProfileProvider(like.uid)).value;
    final name = profile == null
        ? ''
        : (profile.displayName.isNotEmpty
              ? profile.displayName
              : profile.handle);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final at = like.at;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openProfile(
        context,
        ref,
        like.uid,
        handle: profile?.handle ?? '',
        displayName: profile?.displayName ?? '',
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24 * scale,
          vertical: kSpacingPair * scale,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: kAvatarComment / 2 * scale,
              backgroundColor: tokens.surface,
              child: Text(
                initial,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            SizedBox(width: kSpacingBase * scale),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            if (at != null) ...[
              SizedBox(width: kSpacingPair * scale),
              Text(
                RelativeTime.of(at),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
