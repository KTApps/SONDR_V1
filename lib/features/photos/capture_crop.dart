import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;

/// Every stored capture is 3:4 at this size, whatever the camera handed over.
///
/// The app shows a 3:4 viewfinder, so a photo that arrived at the sensor's own
/// ratio and was cropped differently by each surface afterwards was never the
/// picture the person framed. Cropping once, here, makes the viewfinder a
/// promise: what was inside the rectangle is what is stored.
const int kCaptureWidth = 1080;
const int kCaptureHeight = 1440;
const int kCaptureQuality = 80;

/// 3:4, portrait.
const double kCaptureAspect = 3 / 4;

/// Below this, a stop does not open the camera.
///
/// A photo marks a session. Half a minute of a timer that was started by
/// accident is not one, and being asked to photograph it is the app not
/// paying attention.
const int kMinimumCaptureSeconds = 60;

/// Centre-crops [bytes] to 3:4 and re-encodes at [kCaptureWidth] × [kCaptureHeight].
///
/// [mirror] un-mirrors a front-camera frame, which iOS hands back reversed —
/// the preview shows you as a mirror does and the file must not.
///
/// Returns null when the bytes are not a decodable image, which is the only
/// failure a caller can do anything about.
Uint8List? cropToCaptureShape(Uint8List bytes, {bool mirror = false}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Orientation lives in EXIF on an iOS capture; bake it in before measuring,
  // or a landscape-held phone crops the wrong axis.
  final upright = img.bakeOrientation(decoded);
  final source = mirror ? img.flipHorizontal(upright) : upright;

  // The biggest 3:4 rectangle that fits, centred.
  final wide = source.width / source.height > kCaptureAspect;
  final cropWidth = wide ? (source.height * kCaptureAspect).round() : source.width;
  final cropHeight = wide ? source.height : (source.width / kCaptureAspect).round();
  final cropped = img.copyCrop(
    source,
    x: ((source.width - cropWidth) / 2).round(),
    y: ((source.height - cropHeight) / 2).round(),
    width: cropWidth,
    height: cropHeight,
  );

  final resized = img.copyResize(
    cropped,
    width: kCaptureWidth,
    height: kCaptureHeight,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(resized, quality: kCaptureQuality);
}

/// [cropToCaptureShape] on a background isolate.
///
/// Decoding a 12-megapixel JPEG, cropping and re-encoding it is tens of
/// milliseconds of pure Dart, and on the UI thread that is dropped frames on
/// the one screen where the person is waiting to see their photo. compute
/// moves it off; the bytes copy both ways, which costs less than the work.
Future<Uint8List?> cropToCaptureShapeAsync(
  Uint8List bytes, {
  bool mirror = false,
}) => compute(
  (({Uint8List bytes, bool mirror}) a) =>
      cropToCaptureShape(a.bytes, mirror: a.mirror),
  (bytes: bytes, mirror: mirror),
);

/// [cropToCaptureShape] applied to a file on disk, written back in place.
///
/// Returns false when the file could not be decoded; the caller keeps the
/// original rather than losing the capture.
Future<bool> cropCaptureFile(File file, {bool mirror = false}) async {
  final bytes = await file.readAsBytes();
  final out = cropToCaptureShape(bytes, mirror: mirror);
  if (out == null) return false;
  await file.writeAsBytes(out, flush: true);
  return true;
}

/// What a finished session leads to.
///
/// Pulled out of the timer screen so the rules can be read and tested as
/// rules, rather than inferred by driving a stopwatch through a widget test.
class CaptureDecision {
  const CaptureDecision({required this.openCamera, required this.canShare});

  /// False for a session too short to be worth photographing, and for a stop
  /// that credited no task — a photo must never exist without one.
  final bool openCamera;

  /// Sharing needs an account and 20 hours on the task. False means the
  /// review screen is keep-only and says why.
  final bool canShare;

  static const CaptureDecision none = CaptureDecision(
    openCamera: false,
    canShare: false,
  );
}

/// The rules, in one place.
CaptureDecision decideAfterStop({
  required int loggedSeconds,
  required bool hasTask,
  required bool isGuest,
  required int taskTotalSeconds,
  required int milestoneBandSeconds,
}) {
  if (!hasTask || loggedSeconds < kMinimumCaptureSeconds) {
    return CaptureDecision.none;
  }
  return CaptureDecision(
    openCamera: true,
    canShare: !isGuest && taskTotalSeconds >= milestoneBandSeconds,
  );
}
