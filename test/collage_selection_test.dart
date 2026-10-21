import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/photos/collage_selection.dart';
import 'package:sondr/features/photos/models/collage.dart';
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

  group('bandPhotos', () {
    test('returns the FULL band (uncapped), sorted; nulls + adjacent excluded', () {
      final all = [
        for (var i = 0; i < 20; i++) _p((i + 1) * 1000), // band 0, 20 photos
        _p(null, marker: 99), // unassignable → excluded
        _p(30 * 3600, marker: 98), // band 1 → excluded from band 0
      ]..shuffle();
      final band = bandPhotos(all, 20);
      expect(band.length, 20); // uncapped — every band-0 photo
      expect(_cums(band), [for (var i = 0; i < 20; i++) (i + 1) * 1000]); // sorted
    });

    test('collageSelection caps the same band to 9', () {
      final all = [for (var i = 0; i < 20; i++) _p((i + 1) * 1000)];
      expect(bandPhotos(all, 20).length, 20);
      expect(collageSelection(all, 20).length, 9);
    });
  });

  group('one band rule — bandIndexOf', () {
    const h20 = 20 * 3600;

    test('a photo at exactly the boundary completed the milestone (20h band)', () {
      expect(bandIndexOf(_p(h20)), 0);
      expect(_cums(bandPhotos([_p(h20)], 20)), [h20]);
      expect(bandPhotos([_p(h20)], 40), isEmpty);
    });

    test('a photo one second past the boundary opened the next band', () {
      expect(bandIndexOf(_p(h20 + 1)), 1);
      expect(bandPhotos([_p(h20 + 1)], 20), isEmpty);
      expect(_cums(bandPhotos([_p(h20 + 1)], 40)), [h20 + 1]);
    });

    test('the photo taken at the crossing belongs to the milestone it completed, whatever its total says', () {
      final crossing = Photo(
        taskId: 't', taskName: 'T', dayKey: '2020-01-01', timestamp: 99,
        sessionSeconds: 60, photoUrl: '', storagePath: '',
        milestoneHours: 20, cumulativeSeconds: h20 + 6,
      );
      expect(bandIndexOf(crossing), 0);
      expect(bandPhotos([crossing], 20), [crossing]);
      expect(bandPhotos([crossing], 40), isEmpty);
    });

    test('zero and the first second are band 0; null is unplaceable', () {
      expect(bandIndexOf(_p(0)), 0);
      expect(bandIndexOf(_p(1)), 0);
      expect(bandIndexOf(_p(null, marker: 5)), isNull);
    });
  });

  group('the count uses the same rule as the list', () {
    const h20 = 20 * 3600;

    test('one milestone reached: the boundary photo counts, the one past it does not', () {
      final photos = [_p(h20), _p(h20 + 1), _p(10), _p(null, marker: 7)];
      final counted = reachedBandPhotos(photos, 1);
      expect(_cums(counted), unorderedEquals([h20, 10]));
      // and every counted photo is in the 20h stretch's own list
      expect(_cums(bandPhotos(photos, 20)), unorderedEquals(_cums(counted)));
    });

    test('a task with no milestone reached counts nothing', () {
      expect(reachedBandPhotos([_p(10), _p(h20)], 0), isEmpty);
    });
  });

  group('representative photo', () {
    const h20 = 20 * 3600;
    Photo tagged(int ts, {int cum = h20 + 3}) => Photo(
          taskId: 't', taskName: 'T', dayKey: '2020-01-01', timestamp: ts,
          sessionSeconds: 60, photoUrl: '', storagePath: '',
          milestoneHours: 20, cumulativeSeconds: cum,
        );

    test('the crossing photo wins over newer-looking band photos', () {
      final band = bandPhotos([_p(100, marker: 500), tagged(50), _p(3000, marker: 900)], 20);
      expect(representativePhoto(band, 20)?.timestamp, 50);
    });

    test('with no crossing photo, the newest photo in the band', () {
      final band = bandPhotos([_p(100, marker: 500), _p(3000, marker: 900), _p(200, marker: 700)], 20);
      expect(representativePhoto(band, 20)?.timestamp, 900);
    });

    test('an empty band has no representative', () {
      expect(representativePhoto(const [], 20), isNull);
    });
  });

  group('the crossing photo and the collage', () {
    const h20 = 20 * 3600;
    Photo crossing(int ts) => Photo(
          taskId: 't', taskName: 'T', dayKey: '2020-01-01', timestamp: ts,
          sessionSeconds: 60, photoUrl: '', storagePath: '',
          milestoneHours: 20, cumulativeSeconds: h20 + 5,
        );

    test('seeded + crossing, auto-composed: recomposed, and the crossing photo is in it', () {
      final seeded = [_p(1000, marker: 11), _p(5000, marker: 12)];
      final x = crossing(99);
      final band = bandPhotos([...seeded, x], 20);
      final auto = Collage(taskId: 't', milestoneHours: 20, photoIds: [for (final p in seeded) p.id], edited: false);

      final ids = attachCrossingIds(auto, band, x.id);

      expect(ids, [for (final p in band) p.id]);
      expect(ids, contains(x.id));
      expect(ids.last, x.id, reason: 'the crossing photo is the band\'s last');
    });

    test('crossing alone: the band itself holds it, so the stretch shows it', () {
      final x = crossing(99);
      expect(bandPhotos([x], 20).map((p) => p.id), [x.id]);
    });

    test('curated: the owner\'s picks are kept exactly and the crossing photo is appended', () {
      final seeded = [_p(1000, marker: 11), _p(5000, marker: 12), _p(9000, marker: 13)];
      final x = crossing(99);
      final band = bandPhotos([...seeded, x], 20);
      // The owner dropped the middle one.
      final curated = Collage(taskId: 't', milestoneHours: 20, photoIds: [seeded[0].id, seeded[2].id], edited: true);

      final ids = attachCrossingIds(curated, band, x.id);

      expect(ids, [seeded[0].id, seeded[2].id, x.id]);
      expect(ids, isNot(contains(seeded[1].id)), reason: 'a removed pick stays removed');
      expect(attachCrossingIds(Collage(taskId: 't', milestoneHours: 20, photoIds: ids, edited: true), band, x.id), ids,
          reason: 'appending twice appends once');
    });

    test('read time: an existing collage shows its crossing photo without a write', () {
      final seeded = [_p(1000, marker: 11), _p(5000, marker: 12)];
      final x = crossing(99);
      final band = bandPhotos([...seeded, x], 20);
      final shown = [seeded[1], seeded[0]]; // the stored order, whatever it is

      final out = withCrossingPhotos(shown, band, 20);

      expect(out.map((p) => p.id), [seeded[1].id, seeded[0].id, x.id]);
      expect(withCrossingPhotos(out, band, 20).map((p) => p.id), out.map((p) => p.id), reason: 'idempotent');
      expect(withCrossingPhotos(shown, band, 40).map((p) => p.id), shown.map((p) => p.id), reason: 'only this milestone\'s own photo');
    });
  });
}
