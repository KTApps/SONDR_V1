import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/photos/collage_selection.dart';
import 'package:sondr/features/photos/models/photo.dart';

/// A photo with the given cumulative-at-capture. [marker] gives null-cumulative
/// photos a distinct timestamp/id; otherwise the cumulative doubles as the id.
Photo _p(int? cum, {int marker = 0}) => Photo(
      taskId: 't',
      taskName: 'T',
      dayKey: '2020-01-01',
      timestamp: marker != 0 ? marker : (cum ?? -1),
      sessionSeconds: 60,
      photoUrl: '',
      storagePath: '',
      cumulativeSeconds: cum,
    );

List<int?> _cums(List<Photo> ps) => [for (final p in ps) p.cumulativeSeconds];

void main() {
  group('collageSelection', () {
    test('band with 5 photos → all 5, sorted by cumulative', () {
      final photos = [_p(25000), _p(5000), _p(45000), _p(15000), _p(35000)];
      final out = collageSelection(photos, 20);
      expect(_cums(out), [5000, 15000, 25000, 35000, 45000]);
    });

    test('band with exactly 9 → all 9, sorted', () {
      final photos = [for (var i = 0; i < 9; i++) _p((i + 1) * 1000)]..shuffle();
      final out = collageSelection(photos, 20);
      expect(out.length, 9);
      expect(_cums(out), [for (var i = 0; i < 9; i++) (i + 1) * 1000]);
    });

    test('band with 20 → exactly 9: first+last, even spread, chronological, no dupes', () {
      final photos = [for (var i = 0; i < 20; i++) _p((i + 1) * 1000)];
      final out = collageSelection(photos, 20);

      expect(out.length, 9);
      expect(out.first.cumulativeSeconds, 1000); // index 0
      expect(out.last.cumulativeSeconds, 20000); // index 19 (M-1)
      expect(_cums(out),
          [1000, 3000, 6000, 8000, 11000, 13000, 15000, 18000, 20000]);

      final cums = _cums(out).cast<int>();
      expect(cums, orderedEquals([...cums]..sort())); // chronological
      expect(cums.toSet().length, cums.length); // no dupes
    });

    test('null-cumulative photos excluded', () {
      final photos = [
        _p(10000),
        _p(null, marker: 1),
        _p(20000),
        _p(null, marker: 2),
      ];
      expect(_cums(collageSelection(photos, 20)), [10000, 20000]);
    });

    test('locked window: adjacent-band photos excluded both ways', () {
      final all = [
        _p(10000), _p(30000), _p(50000), // band 0  (< 20h)
        _p(30 * 3600), _p(35 * 3600), // band 1  (30h, 35h → 20–40h)
      ];

      // 20h collage = band 0 only.
      final at20 = collageSelection(all, 20);
      expect(_cums(at20), [10000, 30000, 50000]);
      expect(at20.every((p) => p.cumulativeSeconds! < kMilestoneBandSeconds),
          isTrue);

      // 40h collage = band 1 only (the 30h photo belongs here, not to 20h).
      final at40 = collageSelection(all, 40);
      expect(_cums(at40), [30 * 3600, 35 * 3600]);
    });
  });
}
