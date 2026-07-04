import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../shared/photo_tint.dart';
import '../models/photo.dart';

// Collage tint — near-raw (a celebration of the milestone, meant to be enjoyed),
// same whisper as the day-detail Captured thumbnails via the shared matrix.
const double _kCollageSaturation = 0.85;
const Color _kCollageTint = Color(0x1A000000);

/// A milestone collage as a uniform adaptive grid of its photos (1–9). Composed
/// live from the referenced photos, so an edit just re-renders. Column count
/// adapts to keep the grid tidy at every count; tiles are square with a
/// near-raw tint and a graceful per-tile fallback.
class CollageGrid extends StatelessWidget {
  const CollageGrid({
    super.key,
    required this.photos,
    this.spacing = 6,
    this.radius = 10,
  });

  final List<Photo> photos;
  final double spacing;
  final double radius;

  /// 1 → 1 col, 2 → 2, 4 → 2×2, everything else → 3 cols (3/5/6/7/8/9 read
  /// cleanly as rows of three).
  int get _columns {
    final n = photos.length;
    if (n <= 1) return 1;
    if (n == 2) return 2;
    if (n == 4) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _columns,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      children: [
        for (final p in photos) _CollageTile(photo: p, radius: radius),
      ],
    );
  }
}

class _CollageTile extends StatelessWidget {
  const _CollageTile({required this.photo, required this.radius});

  final Photo photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        photo.photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: tokens.ringTrack),
        frameBuilder: (ctx, child, frame, _) {
          if (frame == null) return ColoredBox(color: tokens.surface);
          return Container(
            foregroundDecoration: const BoxDecoration(color: _kCollageTint),
            child: ColorFiltered(
              colorFilter:
                  ColorFilter.matrix(saturationMatrix(_kCollageSaturation)),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
