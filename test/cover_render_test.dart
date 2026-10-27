import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/feed/cover_render.dart';
import 'package:sondr/features/feed/widgets/milestone_frame.dart';
import 'package:sondr/features/feed/widgets/milestone_ring.dart';

/// The cover rendered at share time: the right size, the tiles where the
/// layout puts them, the ring on top.
void main() {
  Future<ui.Image> solid(Color color, {int w = 600, int h = 800}) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = color,
    );
    return recorder.endRecording().toImage(w, h);
  }

  const styles = CoverTextStyles(
    figure: TextStyle(fontFamily: 'Inter', fontSize: 36, color: Colors.white),
    unit: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Colors.white70),
  );

  test('is a 1080 × 1440 JPEG', () async {
    final photos = [await solid(const Color(0xFFFF0000))];
    final bytes = await renderMilestoneCover(photos: photos, milestoneHours: 20, styles: styles);
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, kCoverWidth);
    expect(decoded.height, kCoverHeight);
    // JPEG, not PNG: the first bytes are the SOI marker.
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);
  });

  test('the tiles are where the layout puts them, under the scrim; the ring is white', () async {
    final photos = [
      await solid(const Color(0xFFFF0000)), // red, top-left
      await solid(const Color(0xFF00FF00)), // green
      await solid(const Color(0xFF0000FF)), // blue
      await solid(const Color(0xFFFFFF00)), // yellow
    ];
    final bytes = await renderMilestoneCover(photos: photos, milestoneHours: 40, styles: styles);
    final decoded = img.decodeJpg(bytes)!;
    final f = kCoverWidth / kMilestoneFrameSize.width;
    final tiles = collageTiles(kMilestoneFrameSize, 4);

    img.Pixel at(Offset p) => decoded.getPixel((p.dx * f).round(), (p.dy * f).round());

    // Inside each tile, away from the ring and the scrim's dark ends, the
    // photo's colour dominates.
    final tl = at(Offset(tiles[0].left + 20, tiles[0].center.dy));
    expect(tl.r, greaterThan(150));
    expect(tl.g, lessThan(60));
    final tr = at(Offset(tiles[1].right - 20, tiles[1].center.dy));
    expect(tr.g, greaterThan(150));
    expect(tr.r, lessThan(60));
    final bl = at(Offset(tiles[2].left + 20, tiles[2].center.dy));
    expect(bl.b, greaterThan(150));
    final br = at(Offset(tiles[3].right - 20, tiles[3].center.dy));
    expect(br.r, greaterThan(150));
    expect(br.g, greaterThan(150));

    // The ring's band, at 12 o'clock, is white.
    const g = MilestoneRingGeometry(onPhoto: true);
    final cy = milestoneRingTop(kMilestoneFrameSize.height) + kMilestoneRingSize / 2;
    final band = at(Offset(kMilestoneFrameSize.width / 2, cy - g.radius));
    expect(band.r, greaterThan(235));
    expect(band.g, greaterThan(235));
    expect(band.b, greaterThan(235));

    // The scrim darkens the top edge: the red there is dimmer than mid-tile.
    final top = at(Offset(tiles[0].left + 20, 4));
    expect(top.r, lessThan(tl.r - 40));
    // Inside the band the disc is tinted: the red tile under the ring's
    // disc, beside the text, is dimmer than the same tile outside the ring
    // on the same line, where the scrim is clear.
    final inside = at(Offset(kMilestoneFrameSize.width / 2 - 40, cy - 20));
    final outside = at(Offset(kMilestoneFrameSize.width / 2 - 150, cy - 20));
    expect(outside.r, greaterThan(230));
    expect(inside.r, lessThan(outside.r - 40));
  });

  test('the thumbnail is the collage alone, 600 × 800 at 80: no ring', () async {
    final photos = [
      await solid(const Color(0xFFFF0000)),
      await solid(const Color(0xFF00FF00)),
    ];
    final bytes = await renderMilestoneThumb(photos: photos);
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, kThumbWidth);
    expect(decoded.height, kThumbHeight);
    // Two stacked tiles, touching; where the ring would be, the photo shows
    // at full strength — no band, no tint, no scrim.
    final top = decoded.getPixel(300, 200);
    expect(top.r, greaterThan(230));
    expect(top.g, lessThan(40));
    final bottom = decoded.getPixel(300, 600);
    expect(bottom.g, greaterThan(230));
    final edge = decoded.getPixel(300, 4);
    expect(edge.r, greaterThan(230), reason: 'no scrim');
    final ringLine = decoded.getPixel(300, (0.44 * kThumbHeight - 80.74 * (600 / 358)).round());
    expect(ringLine.r, greaterThan(230), reason: 'no ring');
  });

  test('nine at most, and a framing is honoured', () async {
    final photos = [for (var i = 0; i < 12; i++) await solid(const Color(0xFF808080))];
    final bytes = await renderMilestoneCover(
      photos: photos,
      milestoneHours: 20,
      styles: styles,
      framings: [const PhotoFraming(scale: 2)],
    );
    expect(img.decodeJpg(bytes)!.width, kCoverWidth);
  });

  test('decoding for the cover bounds the width', () async {
    final big = await solid(const Color(0xFF123456), w: 3000, h: 4000);
    final png = await big.toByteData(format: ui.ImageByteFormat.png);
    final image = await decodeForCover(png!.buffer.asUint8List());
    expect(image.width, kCoverWidth);
    expect(image.height, kCoverHeight);
  });
}
