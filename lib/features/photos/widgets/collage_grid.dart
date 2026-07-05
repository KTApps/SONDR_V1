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
    this.removedIds,
    this.onToggleRemove,
    this.canMark,
  });

  final List<Photo> photos;
  final double spacing;
  final double radius;

  /// Edit mode (all three passed together): [removedIds] are the tiles currently
  /// marked for removal (dimmed with an active ×); [onToggleRemove] toggles a
  /// tile; [canMark] gates marking (false → the ×'s disabled, e.g. the last kept
  /// tile). Marking dims **in place** — no reflow — and Save commits. Non-edit
  /// callers pass none → plain tiles.
  final Set<String>? removedIds;
  final void Function(Photo)? onToggleRemove;
  final bool Function(Photo)? canMark;

  /// >9 photos → the dense **mosaic** (more columns, tighter tiles).
  bool get _isMosaic => photos.length > 9;

  /// ≤9: the clean hero layout (1→1, 2→2, 4→2×2, else 3 cols). >9: a mosaic that
  /// densifies as it grows so tiles stay a comfortable size.
  int get _columns {
    final n = photos.length;
    if (n <= 1) return 1;
    if (n == 2) return 2;
    if (n == 4) return 2;
    if (n <= 9) return 3;
    if (n <= 16) return 4;
    if (n <= 25) return 5;
    return 6;
  }

  @override
  Widget build(BuildContext context) {
    // The mosaic tightens spacing and corners so the grid reads as one dense
    // field rather than separate cards.
    final gap = _isMosaic ? 4.0 : spacing;
    final r = _isMosaic ? 6.0 : radius;
    final editing = onToggleRemove != null;
    final removed = removedIds ?? const <String>{};
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _columns,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      children: [
        for (final p in photos)
          _CollageTile(
            photo: p,
            radius: r,
            editing: editing,
            marked: removed.contains(p.id),
            canMark: canMark?.call(p) ?? true,
            onToggle: onToggleRemove == null ? null : () => onToggleRemove!(p),
          ),
      ],
    );
  }
}

class _CollageTile extends StatelessWidget {
  const _CollageTile({
    required this.photo,
    required this.radius,
    this.editing = false,
    this.marked = false,
    this.canMark = true,
    this.onToggle,
  });

  final Photo photo;
  final double radius;
  final bool editing;
  final bool marked;
  final bool canMark;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final image = ClipRRect(
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

    if (!editing) return image;

    // A marked tile can always be un-marked; an un-marked one only if it wouldn't
    // empty the collage (min 1).
    final enabled = marked || canMark;
    return GestureDetector(
      onTap: enabled ? onToggle : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          if (marked)
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: _RemoveBadge(marked: marked, enabled: enabled, tokens: tokens),
          ),
        ],
      ),
    );
  }
}

/// The per-tile removal control: an ×. Bright/filled when marked (this tile will
/// be removed on Save), a subtle dark chip when not, faded when disabled (can't
/// mark the last kept tile).
class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({
    required this.marked,
    required this.enabled,
    required this.tokens,
  });

  final bool marked;
  final bool enabled;
  final GreyscaleTokens tokens;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (marked) {
      bg = tokens.textPrimary;
      fg = tokens.background;
    } else if (enabled) {
      bg = Colors.black.withValues(alpha: 0.5);
      fg = Colors.white;
    } else {
      bg = Colors.black.withValues(alpha: 0.3);
      fg = Colors.white.withValues(alpha: 0.35);
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Icon(Icons.close, size: 13, color: fg),
    );
  }
}
