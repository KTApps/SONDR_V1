import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sondr/features/photos/capture_crop.dart';

/// What the crop costs, measured rather than assumed.
///
/// It runs on a background isolate in the app for this reason: it is tens of
/// milliseconds of pure Dart, and on the UI thread that is dropped frames on
/// the one screen where someone is waiting to see their photo.
void main() {
  test('cropping a full capture frame is reported', () {
    // The frame the chosen preset produces: 1080x1920 portrait.
    final frame = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 1080, height: 1920), quality: 90),
    );

    // Warm, then measure.
    cropToCaptureShape(frame);
    final watch = Stopwatch()..start();
    const runs = 3;
    for (var i = 0; i < runs; i++) {
      final out = cropToCaptureShape(frame);
      expect(out, isNotNull);
    }
    watch.stop();
    final each = watch.elapsedMilliseconds / runs;
    // ignore: avoid_print
    print('CROP 1080x1920 -> ${kCaptureWidth}x$kCaptureHeight: '
        '${each.toStringAsFixed(1)}ms each');

    // Not a performance gate — machines differ — but a ceiling loose enough
    // that only a change of kind would trip it.
    expect(each, lessThan(2000));
  });

  test('the chosen preset needs no upscale', () {
    // 1920x1080 is the preset; portrait that is 1080 wide, and the 3:4 crop
    // of it is exactly what is stored.
    expect(1080, kCaptureWidth);
    expect((1080 / kCaptureAspect).round(), kCaptureHeight);
  });
}
