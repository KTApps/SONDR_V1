import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/photos/milestone_arrangement.dart';
import 'package:sondr/features/photos/models/photo.dart';

import 'tiny_png.dart';

/// The rules of arranging: the default, the nine, the swap, the framing.
void main() {
  Photo photo(int ts) => Photo(
    taskId: 't', taskName: 'Spanish', dayKey: '2026-10-01', timestamp: ts,
    sessionSeconds: 60, photoUrl: 'https://x/$ts.jpg', storagePath: 'p$ts',
  );
  ArrangeEntry band(int ts) => ArrangeEntry(id: photo(ts).id, image: MemoryImage(tinyPng), photo: photo(ts));
  final newShot = ArrangeEntry(id: ArrangeEntry.newShotId, image: MemoryImage(tinyPng), shot: tinyPng);

  final entries = [for (var i = 1; i <= 11; i++) band(i), newShot];

  test('the default is the new photo alone; none without one', () {
    expect(Arrangement.initial(entries).order, [ArrangeEntry.newShotId]);
    expect(Arrangement.initial(entries.sublist(0, 11)).order, isEmpty);
  });

  test('a tap adds, in tap order; a tap again removes; a tenth is refused', () {
    var a = Arrangement.initial(entries);
    a = a.toggled(band(3).id)!;
    a = a.toggled(band(1).id)!;
    expect(a.order, [ArrangeEntry.newShotId, band(3).id, band(1).id]);
    expect(a.positionOf(band(1).id), 3);
    expect(a.positionOf(band(2).id), isNull);
    a = a.toggled(band(3).id)!;
    expect(a.order, [ArrangeEntry.newShotId, band(1).id]);
    for (var i = 2; i <= 8; i++) {
      a = a.toggled(band(i).id)!;
    }
    expect(a.order, hasLength(9));
    expect(a.isFull, isTrue);
    expect(a.toggled(band(9).id), isNull, reason: 'up to 9 photos');
    expect(a.toggled(band(8).id), isNotNull, reason: 'removing is always allowed');
  });

  test('a swap exchanges two positions and keeps the rest', () {
    var a = Arrangement.initial(entries);
    a = a.toggled(band(1).id)!.toggled(band(2).id)!;
    final swapped = a.swapped(0, 2);
    expect(swapped.order, [band(2).id, band(1).id, ArrangeEntry.newShotId]);
    expect(a.swapped(1, 1), a);
    expect(a.swapped(0, 9), a, reason: 'out of range: unchanged');
  });

  test('a framing is kept per photo, within its range, and goes when the photo does', () {
    var a = Arrangement.initial(entries).toggled(band(1).id)!;
    a = a.framed(band(1).id, const PhotoFraming(scale: 5, dx: 0.9, dy: -0.2));
    expect(a.framingOf(band(1).id), const PhotoFraming(scale: 3, dx: 0.5, dy: -0.2));
    expect(a.framingOf(ArrangeEntry.newShotId), PhotoFraming.none);
    expect(a.framingsInOrder(), [PhotoFraming.none, const PhotoFraming(scale: 3, dx: 0.5, dy: -0.2)]);
    a = a.toggled(band(1).id)!;
    expect(a.framings, isEmpty);
  });

  test('the chosen entries come back in collage order', () {
    final a = Arrangement.initial(entries).toggled(band(2).id)!.swapped(0, 1);
    expect(a.chosen(entries).map((e) => e.id), [band(2).id, ArrangeEntry.newShotId]);
  });
}
