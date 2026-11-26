import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../feed_days.dart';
import '../../profile/other_profile_screen.dart';
import '../models/post.dart';
import 'post_chrome.dart' show kTextShadows;

/// What every post card shares: the frame's numbers, the text over the
/// photo, and the header above it — who posted it and one line about it. The milestone card and the session card are one family; this
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
const Color kPostCardTextTime = Color(0xD9FAFAFA); // 85%
const Color kPostCardTextCaption = Color(0xCCFAFAFA); // 80%
const Color kPostCardDotOther = Color(0x59FAFAFA); // 35%

/// Above a card: who posted it — the name without "@", the way to their
/// profile (mine, the Profile tab) — and one line under it in the
/// metadata style. Its left edge is the card's text inset, so the name
/// stands over the words on the photo. The name and the line together are
/// the tap target, at least 44 tall with the air under them.
class PostHeader extends ConsumerWidget {
  const PostHeader({super.key, required this.author, required this.authorUid, required this.line});

  final PostAuthor author;
  final String authorUid;
  final String line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    return GestureDetector(
      key: kPostHeaderKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => openProfile(
        context,
        ref,
        authorUid,
        handle: author.username,
        displayName: author.displayName,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kPostHeaderMinTap),
        child: Padding(
          padding: const EdgeInsets.only(bottom: kPostHeaderToCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                feedName(author),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: kPostHeaderLineGap),
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Key kPostHeaderKey = ValueKey('post-header');

/// The tap target's least height, the name's gap to its line, and the air
/// between the line and the card.
const double kPostHeaderMinTap = 44;
const double kPostHeaderLineGap = 4;
const double kPostHeaderToCard = 10;

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
        style: const TextStyle(fontSize: 13, color: kPostCardTextCaption, shadows: kTextShadows),
      ),
    );
  }
}

/// The task line's style over a photo: 15, bold, with the shadow.
const TextStyle kPostCardTaskStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w700,
  color: kPostCardText,
  shadows: kTextShadows,
);
