import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../shared/photo_tint.dart';
import '../models/post.dart';
import 'post_chrome.dart';

// Match CollageGrid's near-raw tint so the feed collage reads identically to the
// celebration's collage hero (light desaturation + a whisper of dark).
const double _kSaturation = 0.85;
const Color _kTint = Color(0x1A000000);

/// The feed milestone card's photo collage — a post's [PostPhoto]s as a bounded
/// square grid. Mirrors CollageGrid's 1–9 column buckets and tile styling (so it
/// matches the celebration collage), but is PostPhoto-native and **caps at 9
/// tiles (3×3)**: a post with >9 photos shows 9 with a "+N" overlay on the last
/// tile, so a feed card never grows an unbounded tall mosaic. Only used for 2+
/// photos — 1 photo stays the single-photo backdrop, 0 the ring card.
class PostCollage extends StatelessWidget {
  const PostCollage({super.key, required this.photos});

  final List<PostPhoto> photos;

  static const int _cap = 9;

  int get _shownCount => photos.length > _cap ? _cap : photos.length;
  int get _overflow => photos.length > _cap ? photos.length - _cap : 0;

  /// Column buckets, matching CollageGrid over the shown (≤9) tiles: 2→2, 4→2,
  /// everything else (3, 5–9) → 3.
  int get _columns {
    final n = _shownCount;
    if (n == 2) return 2;
    if (n == 4) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final shown = photos.take(_shownCount).toList();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _columns,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < shown.length; i++)
          _Tile(
            url: shown[i].url,
            // "+N" on the last tile when the post has more than 9 photos.
            overflow: (i == shown.length - 1) ? _overflow : 0,
          ),
      ],
    );
  }
}

/// One square collage tile: the photo (asset for mocks / cached network for real
/// Storage urls via [postImageProvider]) under the near-raw collage tint, with an
/// optional "+N more" overlay for the overflow tile.
class _Tile extends StatelessWidget {
  const _Tile({required this.url, this.overflow = 0});

  final String url;
  final int overflow;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: postImageProvider(url),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: tokens.ringTrack),
            frameBuilder: (ctx, child, frame, _) {
              if (frame == null) return ColoredBox(color: tokens.surface);
              return Container(
                foregroundDecoration: const BoxDecoration(color: _kTint),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(
                    saturationMatrix(_kSaturation),
                  ),
                  child: child,
                ),
              );
            },
          ),
          if (overflow > 0)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
