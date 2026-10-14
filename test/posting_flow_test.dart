import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/photos/capture_crop.dart';

/// The rules the posting journey is built on, held where they can be read.
void main() {
  test('a session under a minute does not open the camera', () {
    // The timer checks loggedSeconds against this before anything else.
    expect(kMinimumCaptureSeconds, 60);
    expect(59 < kMinimumCaptureSeconds, isTrue);
    expect(60 < kMinimumCaptureSeconds, isFalse);
  });

  test('the stored shape and the viewfinder are one number', () {
    expect(kCaptureAspect, 3 / 4);
    expect(kCaptureWidth / kCaptureHeight, closeTo(kCaptureAspect, 0.0001));
  });
}
