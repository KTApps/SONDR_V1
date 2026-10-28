import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/relative_time.dart';
import '../../profile/other_profile_screen.dart';
import '../models/post.dart';

/// What every post card shares: the frame's numbers, the text over the
/// photo, and the top row — the handle at the left, how long ago at the
/// right. The milestone card and the session card are one family; this
/// is the family resemblance.

/// The frame's corner, as the milestone card has always been cut.
const double kPostCardRadius = 24;

/// Air from the frame's edge to the text.
const double kPostCardInset = 18;
const double kPostCardTop = 16;
const double kPostCardBottom = 16;

/// Text over the photo. Fixed, not theme tokens: the ground is the photo,
/// not the surface, and the scrim holds the contrast.
const Color kPostCardText = Color(0xFFFAFAFA);
const Color kPostCardTextTime = Color(0xB3FAFAFA); // 70%
const Color kPostCardTextCaption = Color(0xCCFAFAFA); // 80%
const Color kPostCardDotOther = Color(0x59FAFAFA); // 35%

/// The handle, the way to whoever posted, and how long ago at the right.
class PostCardTopRow extends ConsumerWidget {
  const PostCardTopRow({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = post.author;
    final handle = author.username.isNotEmpty ? author.username : author.label;
    final createdAt = post.createdAt;
    return Row(
      children: [
        // The handle takes the line; the time sits at the right inset.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openProfile(
              context,
              ref,
              post.authorUid,
              handle: author.username,
              displayName: author.displayName,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kPostCardText,
                ),
              ),
            ),
          ),
        ),
        if (createdAt != null) ...[
          const SizedBox(width: 12),
          IgnorePointer(
            child: Text(
              RelativeTime.of(createdAt),
              style: const TextStyle(fontSize: 13, color: kPostCardTextTime),
            ),
          ),
        ],
      ],
    );
  }
}

/// The caption, two lines and cut, until it is tapped: then the whole
/// of it, in place, and a tap folds it back. The same on every card.
class PostCardCaption extends StatefulWidget {
  const PostCardCaption({super.key, required this.text});

  final String text;

  @override
  State<PostCardCaption> createState() => _PostCardCaptionState();
}

class _PostCardCaptionState extends State<PostCardCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.text,
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: kPostCardTextCaption),
      ),
    );
  }
}
