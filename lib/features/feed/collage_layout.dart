import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The milestone cover's collage: how a post's photos tile its 3:4 frame.
///
/// Pure, so every layout is tested without a widget: rows of tiles by
/// count, each row's share of the height, the gap, and where each tile
/// lands. The photos go in stored order — oldest first — left to right,
/// then down. At most nine; a tenth is not shown.

/// How many photos a collage holds at most.
const int kCollageMax = 9;

/// The space between tiles, in points of the frame. None: the photos
/// touch, and the collage reads as one picture.
const double kCollageGap = 0;

/// Tiles per row, by photo count: `rows(5)` is `[2, 3]`.
List<int> collageRows(int count) => switch (count.clamp(0, kCollageMax)) {
  0 => const [],
  1 => const [1],
  2 => const [1, 1],
  3 => const [1, 2],
  4 => const [2, 2],
  5 => const [2, 3],
  6 => const [2, 2, 2],
  7 => const [2, 3, 2],
  8 => const [2, 3, 3],
  _ => const [3, 3, 3],
};

/// Each row's share of the frame's height. Equal, except three photos,
/// whose single tile above the pair takes 62%.
List<double> collageRowHeights(int count) {
  final rows = collageRows(count);
  if (rows.isEmpty) return const [];
  if (count == 3) return const [0.62, 0.38];
  return List<double>.filled(rows.length, 1 / rows.length);
}

/// Where each tile sits in a frame of [size], in order.
List<Rect> collageTiles(Size size, int count, {double gap = kCollageGap}) {
  final rows = collageRows(count);
  final heights = collageRowHeights(count);
  if (rows.isEmpty) return const [];
  final innerHeight = size.height - gap * (rows.length - 1);
  final out = <Rect>[];
  var top = 0.0;
  for (var r = 0; r < rows.length; r++) {
    final n = rows[r];
    final h = innerHeight * heights[r];
    final w = (size.width - gap * (n - 1)) / n;
    for (var k = 0; k < n; k++) {
      out.add(Rect.fromLTWH(k * (w + gap), top, w, h));
    }
    top += h + gap;
  }
  return out;
}

/// How one photo is framed in its tile: a zoom on the centred cover crop,
/// and a nudge as fractions of the tile's width and height. Build 2 lets
/// the author set these; until then every photo takes the default, which
/// is the plain cover crop.
@immutable
class PhotoFraming {
  const PhotoFraming({this.scale = 1, this.dx = 0, this.dy = 0});

  static const PhotoFraming none = PhotoFraming();

  /// 1 is the cover crop; larger zooms in on it.
  final double scale;

  /// How far the photo is moved, as a fraction of the tile: positive moves
  /// it right and down.
  final double dx;
  final double dy;

  /// The zoom's range: the cover crop, up to three times it.
  static const double minScale = 1;
  static const double maxScale = 3;

  /// The same framing with its zoom kept to the range and its nudge kept
  /// to half a tile, so no part of the tile is ever left bare.
  PhotoFraming clamped() => PhotoFraming(
    scale: scale.clamp(minScale, maxScale),
    dx: dx.clamp(-0.5, 0.5),
    dy: dy.clamp(-0.5, 0.5),
  );

  Map<String, double> toMap() => {'scale': scale, 'dx': dx, 'dy': dy};

  /// Null, or a malformed map, is the plain cover crop.
  static PhotoFraming fromMap(dynamic map) {
    if (map is! Map) return none;
    double n(String k, double d) => map[k] is num ? (map[k] as num).toDouble() : d;
    return PhotoFraming(scale: n('scale', 1), dx: n('dx', 0), dy: n('dy', 0));
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoFraming &&
      other.scale == scale &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(scale, dx, dy);

  @override
  String toString() => 'PhotoFraming(scale: $scale, dx: $dx, dy: $dy)';
}

/// The part of an image of [image] size that shows in a tile of [tile]
/// size under [framing]: the cover crop, zoomed about the tile's centre and
/// nudged. What a canvas draws from, and what the widget's transform shows.
Rect coverSourceRect(Size image, Size tile, PhotoFraming framing) {
  final s = (tile.width / image.width > tile.height / image.height
          ? tile.width / image.width
          : tile.height / image.height) *
      framing.scale;
  final w = tile.width / s;
  final h = tile.height / s;
  // Moving the photo right by dx of the tile shows a region further left.
  final cx = image.width / 2 - framing.dx * tile.width / s;
  final cy = image.height / 2 - framing.dy * tile.height / s;
  return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
}
