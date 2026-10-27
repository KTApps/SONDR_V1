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

    test('two stack, touching', () {
      final t = collageTiles(frame, 2);
      expect(t[0], const Rect.fromLTWH(0, 0, 300, 200));
      expect(t[1], const Rect.fromLTWH(0, 200, 300, 200));
    });

    test('three: one above a pair, 62 / 38', () {
      final t = collageTiles(frame, 3);
      expect(t[0].height, closeTo(400 * 0.62, 1e-9));
      expect(t[0].width, 300);
      expect(t[1].top, closeTo(400 * 0.62, 1e-9));
      expect(t[1].width, 150);
      expect(t[2].left, 150);
      expect(t[1].bottom, 400);
    });

    test('a gap, when one is asked for, sits between the tiles', () {
      final t = collageTiles(frame, 2, gap: 2);
      expect(t[0], const Rect.fromLTWH(0, 0, 300, 199));
      expect(t[1], const Rect.fromLTWH(0, 201, 300, 199));
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
      // Equal cells, touching.
      expect(t[1].left - t[0].right, closeTo(0, 1e-9));
      expect(t[3].top - t[0].bottom, closeTo(0, 1e-9));
    });

    test('seven: two, three, two', () {
      final t = collageTiles(frame, 7);
      expect(t[0].width, 150);
      expect(t[2].width, closeTo(100, 1e-9));
      expect(t[5].width, 150);
      expect(t[6].bottom, closeTo(400, 1e-9));
    });

    test('the tiles tile: nothing overlaps and the frame is covered exactly', () {
      for (var n = 1; n <= 9; n++) {
        final t = collageTiles(frame, n);
        final area = t.fold<double>(0, (s, r) => s + r.width * r.height);
        expect(area, closeTo(300 * 400, 1e-6), reason: '$n photos');
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
