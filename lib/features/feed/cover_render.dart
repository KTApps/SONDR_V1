import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'collage_layout.dart';
import 'widgets/milestone_frame.dart';
import 'widgets/milestone_ring.dart';

/// The milestone's cover as one image, made at share time: the collage,
/// the scrim and the ring with the hours — the picture the card shows for
/// its first page, and what a share to another app would send. The same
/// figures the card draws with, on a canvas, at [kCoverWidth] across.

/// The cover's size: 3:4 at 1080 across.
const int kCoverWidth = 1080;
const int kCoverHeight = 1440;

/// JPEG quality.
const int kCoverQuality = 85;

/// The thumbnail — the collage alone, no ring, no scrim, no text — for the
/// strips and the thumbs: 3:4 at 600 across, at 80.
const int kThumbWidth = 600;
const int kThumbHeight = 800;
const int kThumbQuality = 80;

/// The ring's two texts, in the styles the card draws them — captured
/// from a context before the share leaves the screen.
@immutable
class CoverTextStyles {
  const CoverTextStyles({required this.figure, required this.unit});

  final TextStyle? figure;
  final TextStyle? unit;

  static CoverTextStyles of(BuildContext context) => CoverTextStyles(
    figure: MilestoneRingCentre.figureStyle(context, onPhoto: true),
    unit: MilestoneRingCentre.unitStyle(context, onPhoto: true),
  );
}

/// The surface under the tiles, for a photo that fails to draw.
const Color _kSurface = Color(0xFF161616);

/// The ring's fill over a photo.
const Color _kRingFill = Color(0xFFFAFAFA);

/// Paint the collage alone onto [canvas] at the reference frame size: the
/// tiles, each its photo's cover crop, zoomed and nudged as framed.
void paintMilestoneCollage(
  Canvas canvas, {
  required List<ui.Image> photos,
  List<PhotoFraming>? framings,
}) {
  final size = kMilestoneFrameSize;
  canvas.drawRect(Offset.zero & size, Paint()..color = _kSurface);
  final shown = photos.take(kCollageMax).toList();
  final tiles = collageTiles(size, shown.length);
  final paint = Paint()..filterQuality = FilterQuality.high;
  for (var i = 0; i < tiles.length; i++) {
    final image = shown[i];
    final framing =
        framings != null && i < framings.length ? framings[i] : PhotoFraming.none;
    final src = coverSourceRect(
      Size(image.width.toDouble(), image.height.toDouble()),
      tiles[i].size,
      framing,
    );
    canvas.save();
    canvas.clipRect(tiles[i]);
    canvas.drawImageRect(image, src, tiles[i], paint);
    canvas.restore();
  }
}

/// Paint the cover onto [canvas] at the reference frame size — the card's
/// width on the reference phone — so the composition is the card's exactly;
/// the caller scales the canvas to the output.
void paintMilestoneCover(
  Canvas canvas, {
  required List<ui.Image> photos,
  required int milestoneHours,
  required CoverTextStyles styles,
  List<PhotoFraming>? framings,
}) {
  final size = kMilestoneFrameSize;
  final frame = Offset.zero & size;
  paintMilestoneCollage(canvas, photos: photos, framings: framings);

  // The scrim.
  canvas.drawRect(
    frame,
    Paint()..shader = kMilestoneScrim.createShader(frame),
  );

  // The ring, at the card's place.
  const geometry = MilestoneRingGeometry(onPhoto: true);
  final centre = Offset(
    size.width / 2,
    milestoneRingTop(size.height) + kMilestoneRingSize / 2,
  );
  paintMilestoneRing(canvas, centre, geometry, _kRingFill);

  // The hours over the word, centred in the ring, at the one size every
  // page uses — the styles are the card's own.
  final figure = TextPainter(
    text: TextSpan(text: '$milestoneHours', style: styles.figure),
    textDirection: TextDirection.ltr,
  )..layout();
  final unit = TextPainter(
    text: TextSpan(text: 'hours', style: styles.unit),
    textDirection: TextDirection.ltr,
  )..layout();
  final total = figure.height + unit.height;
  final top = centre.dy - total / 2;
  figure.paint(canvas, Offset(centre.dx - figure.width / 2, top));
  unit.paint(canvas, Offset(centre.dx - unit.width / 2, top + figure.height));
  figure.dispose();
  unit.dispose();
}

/// The cover as JPEG bytes, [kCoverWidth] × [kCoverHeight] at [kCoverQuality].
Future<Uint8List> renderMilestoneCover({
  required List<ui.Image> photos,
  required int milestoneHours,
  required CoverTextStyles styles,
  List<PhotoFraming>? framings,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(kCoverWidth / kMilestoneFrameSize.width);
  paintMilestoneCover(
    canvas,
    photos: photos,
    milestoneHours: milestoneHours,
    styles: styles,
    framings: framings,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(kCoverWidth, kCoverHeight);
  picture.dispose();
  try {
    return await _jpeg(image, quality: kCoverQuality);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _jpeg(ui.Image image, {required int quality}) async {
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (rgba == null) throw StateError('the image could not be read back');
  final encoded = img.encodeJpg(
    img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      numChannels: 4,
    ),
    quality: quality,
  );
  return Uint8List.fromList(encoded);
}

/// The thumbnail as JPEG bytes, [kThumbWidth] × [kThumbHeight] at
/// [kThumbQuality]: the collage and nothing else.
Future<Uint8List> renderMilestoneThumb({
  required List<ui.Image> photos,
  List<PhotoFraming>? framings,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(kThumbWidth / kMilestoneFrameSize.width);
  paintMilestoneCollage(canvas, photos: photos, framings: framings);
  final picture = recorder.endRecording();
  final image = await picture.toImage(kThumbWidth, kThumbHeight);
  picture.dispose();
  try {
    return await _jpeg(image, quality: kThumbQuality);
  } finally {
    image.dispose();
  }
}

/// Decode a photo's bytes for the cover, no wider than the cover itself.
Future<ui.Image> decodeForCover(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: kCoverWidth);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}
