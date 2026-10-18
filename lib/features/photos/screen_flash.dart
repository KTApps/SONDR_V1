import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// The front camera's flash: the screen itself.
///
/// There is no lamp on that side, so the light has to come from the display
/// — a white sheet over everything at full brightness, held across the
/// shutter. An interface because a widget test has no screen to brighten,
/// and because getting the restore wrong leaves someone's phone at full
/// brightness after they have left the camera.
abstract class ScreenFlash {
  /// Take the screen to full brightness, remembering what it was.
  Future<void> raise();

  /// Put it back. Safe to call when [raise] never ran or already failed.
  Future<void> restore();
}

class DeviceScreenFlash implements ScreenFlash {
  final ScreenBrightness _brightness = ScreenBrightness();
  bool _raised = false;

  @override
  Future<void> raise() async {
    if (_raised) return;
    try {
      await _brightness.setApplicationScreenBrightness(1);
      _raised = true;
    } catch (e) {
      debugPrint('SONDR brightness error: ${e.runtimeType} :: $e');
    }
  }

  @override
  Future<void> restore() async {
    // Unconditionally, not only when _raised: a reset that was never needed
    // costs nothing, and a screen left at full costs the battery and the
    // trust of whoever is holding it.
    _raised = false;
    try {
      await _brightness.resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('SONDR brightness error: ${e.runtimeType} :: $e');
    }
  }
}
