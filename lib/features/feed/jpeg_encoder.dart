import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// JPEG encoding off the UI thread. The cover and the thumbnail are 1.5
/// and 0.5 megapixels; the `image` package's encoder, pure Dart on the UI
/// isolate, froze the screen for a second or two per image.
abstract class JpegEncoder {
  Future<Uint8List> encode(ui.Image image, {required int quality});
}

/// The platform's encoder (ImageIO on iOS) by way of flutter_image_compress:
/// the image goes out of the engine as PNG — a native encode, off the UI
/// thread — and comes back as JPEG at [quality]. Where the plugin is not
/// there (a test), the Dart encoder on a background isolate stands in.
class PlatformJpegEncoder implements JpegEncoder {
  const PlatformJpegEncoder();

  static const _fallback = IsolateJpegEncoder();

  @override
  Future<Uint8List> encode(ui.Image image, {required int quality}) async {
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('the image could not be read back');
      final out = await FlutterImageCompress.compressWithList(
        png.buffer.asUint8List(),
        quality: quality,
        format: CompressFormat.jpeg,
        minWidth: image.width,
        minHeight: image.height,
        keepExif: false,
      );
      if (out.isEmpty) throw StateError('the platform encoder gave nothing back');
      return out;
    } catch (e) {
      debugPrint('SONDR platform JPEG encoder unavailable: ${e.runtimeType}; using Dart');
      return _fallback.encode(image, quality: quality);
    }
  }
}

/// The `image` package's encoder, on its own isolate so the UI never waits.
class IsolateJpegEncoder implements JpegEncoder {
  const IsolateJpegEncoder();

  @override
  Future<Uint8List> encode(ui.Image image, {required int quality}) async {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) throw StateError('the image could not be read back');
    final width = image.width;
    final height = image.height;
    final bytes = rgba.buffer.asUint8List();
    return Isolate.run(() => _encode(bytes, width, height, quality));
  }

  static Uint8List _encode(Uint8List rgba, int width, int height, int quality) =>
      Uint8List.fromList(
        img.encodeJpg(
          img.Image.fromBytes(width: width, height: height, bytes: rgba.buffer, numChannels: 4),
          quality: quality,
        ),
      );
}
