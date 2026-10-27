import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/collage_layout.dart';

/// How a milestone's photos tile its frame.
void main() {
  test('rows by count', () {
    expect(collageRows(0), isEmpty);
    expect(collageRows(1), [1]);
    expect(collageRows(2), [1, 1]);
    expect(collageRows(3), [1, 2]);
    expect(collageRows(4), [2, 2]);
    expect(collageRows(5), [2, 3]);
    expect(collageRows(6), [2, 2, 2]);
    expect(collageRows(7), [2, 3, 2]);
    expect(collageRows(8), [2, 3, 3]);
    expect(collageRows(9), [3, 3, 3]);
    expect(collageRows(12), [3, 3, 3], reason: 'nine at most');
  });

  test('rows share the height equally, except three', () {
    expect(collageRowHeights(2), [0.5, 0.5]);
    expect(collageRowHeights(3), [0.62, 0.38]);
    expect(collageRowHeights(6), [1 / 3, 1 / 3, 1 / 3]);
    expect(collageRowHeights(1), [1]);
  });

  group('tiles in a 300 × 400 frame', () {
    const frame = Size(300, 400);

    test('one photo fills it', () {
      expect(collageTiles(frame, 1), [const Rect.fromLTWH(0, 0, 300, 400)]);
    });

    test('two stack, with the gap between', () {
      final t = collageTiles(frame, 2);
      expect(t[0], const Rect.fromLTWH(0, 0, 300, 199));
      expect(t[1], const Rect.fromLTWH(0, 201, 300, 199));
    });

    test('three: one above a pair, 62 / 38', () {
      final t = collageTiles(frame, 3);
      expect(t[0].height, closeTo(398 * 0.62, 1e-9));
      expect(t[0].width, 300);
      expect(t[1].top, closeTo(398 * 0.62 + 2, 1e-9));
      expect(t[1].width, 149);
      expect(t[2].left, 151);
      expect(t[1].bottom, 400);
    });

    test('nine: a three by three, in reading order', () {
      final t = collageTiles(frame, 9);
      expect(t, hasLength(9));
      // Row 0 left to right, then row 1.
      expect(t[0].left, 0);
      expect(t[1].left, greaterThan(t[0].left));
      expect(t[2].left, greaterThan(t[1].left));
      expect(t[3].top, greaterThan(t[0].top));
      expect(t[3].left, 0);
      expect(t[8].bottom, closeTo(400, 1e-9));
      expect(t[8].right, closeTo(300, 1e-9));
      // Equal cells, two-point gaps.
      expect(t[1].left - t[0].right, closeTo(2, 1e-9));
      expect(t[3].top - t[0].bottom, closeTo(2, 1e-9));
    });

    test('seven: two, three, two', () {
      final t = collageTiles(frame, 7);
      expect(t[0].width, 149);
      expect(t[2].width, closeTo((300 - 4) / 3, 1e-9));
      expect(t[5].width, 149);
      expect(t[6].bottom, closeTo(400, 1e-9));
    });

    test('the tiles tile: nothing overlaps and the frame is covered', () {
      for (var n = 1; n <= 9; n++) {
        final t = collageTiles(frame, n);
        final area = t.fold<double>(0, (s, r) => s + r.width * r.height);
        final rows = collageRows(n);
        final gaps = 2.0 * (rows.length - 1) * 300 + [for (final k in rows) 2.0 * (k - 1)].fold<double>(0, (s, g) => s + g) * (398 / rows.length);
        expect(area, lessThanOrEqualTo(300 * 400 + 1e-6));
        expect(area, greaterThan(300 * 400 - gaps - 1e-6), reason: '$n photos');
        for (var i = 0; i < t.length; i++) {
          for (var j = i + 1; j < t.length; j++) {
            expect(t[i].overlaps(t[j]), isFalse, reason: '$n photos: $i and $j');
          }
        }
      }
    });
  });

  group('the cover crop', () {
    test('a wide photo in a tall tile shows its middle, full height', () {
      final r = coverSourceRect(const Size(2000, 1000), const Size(300, 400), PhotoFraming.none);
      expect(r.height, 1000);
      expect(r.width, 750);
      expect(r.center, const Offset(1000, 500));
    });

    test('zoom shows less, about the centre; a nudge right shows further left', () {
      final zoomed = coverSourceRect(const Size(2000, 1000), const Size(300, 400), const PhotoFraming(scale: 2));
      expect(zoomed.width, 375);
      expect(zoomed.height, 500);
      expect(zoomed.center, const Offset(1000, 500));
      final nudged = coverSourceRect(const Size(2000, 1000), const Size(300, 400), const PhotoFraming(dx: 0.25));
      // Moved right by a quarter of the tile: 75 tile points, 187.5 image points.
      expect(nudged.center.dx, closeTo(1000 - 187.5, 1e-9));
    });
  });
}
