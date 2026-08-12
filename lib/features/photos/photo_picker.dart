import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/debug_flags.dart';

/// The downscale target — 1080px wide, quality 80 — shared by every capture path
/// so uploads are identically sized.
const int _kMaxWidth = 1080;
const int _kQuality = 80;

/// **Camera-only** capture — the app's *sole* capture path (session captures and
/// milestone captures alike): opens the system camera directly and downscales.
/// The photo library is NEVER offered anywhere; there is no `ImageSource.gallery`
/// path in the app. This keeps every gallery photo an in-the-moment capture, so a
/// milestone collage composed from them can't smuggle in a library import.
/// Returns the file, or null if the user backed out or the camera failed.
///
/// The iOS simulator has no camera, so in **kDebugTools builds only** a bundled
/// mock photo is injected instead, to make the flow drivable on the sim. That
/// branch is guarded by `kDebugTools` (= `bool.fromEnvironment('DEBUG_TOOLS')`,
/// const-false in any release build), so it tree-shakes out entirely and is
/// UNREACHABLE in release — a mock photo can never reach a real post.
Future<File?> captureFromCamera(BuildContext context) async {
  if (kDebugTools) {
    return _mockCameraCapture();
  }
  final XFile? shot;
  try {
    shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: _kMaxWidth.toDouble(),
      imageQuality: _kQuality,
    );
  } catch (e) {
    debugPrint('SONDR camera error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Couldn’t open the camera.')),
        );
    }
    return null;
  }
  if (shot == null) return null; // backed out of the camera
  return File(shot.path);
}

/// Debug-only stand-in for [captureFromCamera] on the cameraless simulator.
/// Alternates the two bundled mock photos across successive calls (so a retake
/// visibly changes). Only ever reached under `kDebugTools`.
int _mockCaptureCount = 0;
Future<File?> _mockCameraCapture() async {
  final even = _mockCaptureCount % 2 == 0;
  _mockCaptureCount++;
  final asset = even ? 'assets/mock/sample1.jpg' : 'assets/mock/sample2.jpg';
  final bytes = await rootBundle.load(asset);
  final dir = Directory.systemTemp.createTempSync('sondr_mockcap');
  final file = File('${dir.path}/mock.jpg')
    ..writeAsBytesSync(bytes.buffer.asUint8List());
  return file;
}
