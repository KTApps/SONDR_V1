import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/photos/collages_repository.dart';
import 'package:sondr/features/photos/models/collage.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photo_viewer_sets.dart';

Photo _photo(int ts, {int? hours}) => Photo(
      taskId: 'golf', taskName: 'Golf', dayKey: '2026-10-01', timestamp: ts,
      sessionSeconds: 60, photoUrl: '', storagePath: '',
      milestoneHours: hours, cumulativeSeconds: ts,
    );

void main() {
  group('the band set', () {
    test('is what the detail shows, then the rest of the stretch in capture order', () {
      // The band: five photos. The collage shows the 2nd and 4th, plus the
      // crossing photo (added back at read time).
      final band = [for (var t = 1; t <= 5; t++) _photo(t)];
      final crossing = _photo(9, hours: 20);
      final detail = BandDetail(
        collage: Collage(taskId: 'golf', milestoneHours: 20, photoIds: ['b', 'd'], edited: true),
        photos: [band[1], band[3], crossing],
        band: [...band, crossing],
      );
      expect(bandViewerSet(detail).map((p) => p.timestamp), [2, 4, 9, 1, 3, 5]);
    });

    test('with no collage it is the whole stretch, once', () {
      final band = [for (var t = 1; t <= 3; t++) _photo(t)];
      final detail = BandDetail(collage: null, photos: band, band: band);
      expect(bandViewerSet(detail).map((p) => p.timestamp), [1, 2, 3]);
    });

    test('a detail handed without its band still opens on what it shows', () {
      final shown = [_photo(1), _photo(2)];
      expect(bandViewerSet(BandDetail(collage: null, photos: shown)).length, 2);
    });
  });

  test('a month or a day is exactly its display order', () {
    final shown = [_photo(5), _photo(2), _photo(7)];
    expect(displayedViewerSet(shown).map((p) => p.timestamp), [5, 2, 7]);
    expect(displayedViewerSet(shown), isNot(same(shown)));
  });

  test('the start index is the tapped photo, or the first if it is not in the set', () {
    final set = [_photo(1), _photo(2), _photo(3)];
    expect(viewerIndexOf(set, set[2]), 2);
    expect(viewerIndexOf(set, _photo(99)), 0);
  });
}
