import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sondr/features/photos/capture_crop.dart';

/// Every stored capture is 3:4.
///
/// The viewfinder shows a 3:4 rectangle; if the file kept the sensor's own
/// shape, every surface downstream cropped it differently and none of them
/// matched what was framed.
void main() {
  Uint8List jpeg(int width, int height, {int Function(int x, int y)? paint}) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = paint?.call(x, y) ?? 128;
        image.setPixelRgb(x, y, v, v, v);
      }
    }
    return img.encodeJpg(image, quality: 95);
  }

  test('a landscape frame comes out 3:4', () {
    final out = cropToCaptureShape(jpeg(4032, 3024));
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, kCaptureWidth);
    expect(decoded.height, kCaptureHeight);
    expect(decoded.width / decoded.height, closeTo(3 / 4, 0.0001));
  });

  test('a portrait frame comes out 3:4', () {
    final decoded = img.decodeImage(cropToCaptureShape(jpeg(3024, 4032))!)!;
    expect(decoded.width, kCaptureWidth);
    expect(decoded.height, kCaptureHeight);
  });

  test('a square frame comes out 3:4', () {
    final decoded = img.decodeImage(cropToCaptureShape(jpeg(2000, 2000))!)!;
    expect(decoded.width / decoded.height, closeTo(3 / 4, 0.0001));
  });

  test('the crop is CENTRED, not from a corner', () {
    // A 4000x3000 frame crops to 2250 wide starting at x=875, so a dark
    // band narrower than that offset survives only if the crop started at
    // the corner — which is the mistake this guards.
    const width = 4000, height = 3000;
    final bytes = jpeg(width, height, paint: (x, y) => x < 800 ? 0 : 255);
    final decoded = img.decodeImage(cropToCaptureShape(bytes)!)!;
    final left = decoded.getPixel(4, decoded.height ~/ 2);
    expect(left.r, greaterThan(200), reason: 'the dark edge survived the crop');
  });

  test('un-mirroring flips the frame', () {
    // Bright on the left only. Mirrored, it must come out on the right.
    const width = 3000, height = 4000;
    final bytes = jpeg(width, height, paint: (x, y) => x < width ~/ 2 ? 255 : 0);
    final plain = img.decodeImage(cropToCaptureShape(bytes)!)!;
    final flipped = img.decodeImage(cropToCaptureShape(bytes, mirror: true)!)!;
    final y = plain.height ~/ 2;
    expect(plain.getPixel(20, y).r, greaterThan(200));
    expect(flipped.getPixel(20, y).r, lessThan(60));
    expect(flipped.getPixel(flipped.width - 20, y).r, greaterThan(200));
  });

  test('undecodable bytes are reported, not thrown', () {
    expect(cropToCaptureShape(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test('the file form rewrites in place and keeps the original on failure',
      () async {
    final dir = Directory.systemTemp.createTempSync('sondr_crop');
    addTearDown(() => dir.deleteSync(recursive: true));

    final good = File('${dir.path}/good.jpg')..writeAsBytesSync(jpeg(4000, 3000));
    expect(await cropCaptureFile(good), isTrue);
    final decoded = img.decodeImage(good.readAsBytesSync())!;
    expect(decoded.width, kCaptureWidth);
    expect(decoded.height, kCaptureHeight);

    final bad = File('${dir.path}/bad.jpg')..writeAsBytesSync(Uint8List(8));
    expect(await cropCaptureFile(bad), isFalse);
    expect(bad.lengthSync(), 8, reason: 'a failed crop destroyed the capture');
  });
}
