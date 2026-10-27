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

  group('what a finished session leads to', () {
    const band = 20 * 3600;
    CaptureDecision decide({
      int logged = 120,
      bool hasTask = true,
      bool isGuest = false,
      int total = band,
    }) => decideAfterStop(
      loggedSeconds: logged,
      hasTask: hasTask,
      isGuest: isGuest,
      taskTotalSeconds: total,
      milestoneBandSeconds: band,
    );

    test('under a minute opens no camera', () {
      expect(decide(logged: 59).openCamera, isFalse);
      expect(decide(logged: 1).openCamera, isFalse);
      expect(decide(logged: 0).openCamera, isFalse);
    });

    test('a minute or more opens it', () {
      expect(decide(logged: 60).openCamera, isTrue);
      expect(decide(logged: 3600).openCamera, isTrue);
    });

    test('no task credited means no camera — a photo needs something to '
        'belong to', () {
      expect(decide(hasTask: false).openCamera, isFalse);
      expect(decide(hasTask: false, logged: 7200).openCamera, isFalse);
    });

    test('a guest can never share, however long the task', () {
      expect(decide(isGuest: true, total: band * 5).openCamera, isTrue);
      expect(decide(isGuest: true, total: band * 5).canShare, isFalse);
    });

    test('under 20h cannot share, signed in or not', () {
      expect(decide(total: band - 1).canShare, isFalse);
      expect(decide(total: 0).canShare, isFalse);
      expect(decide(isGuest: true, total: band - 1).canShare, isFalse);
    });

    test('20h and an account is the only way to share', () {
      expect(decide(total: band).canShare, isTrue);
      expect(decide(total: band * 3).canShare, isTrue);
    });

    test('a decision that opens no camera never shares', () {
      for (final d in [
        decide(logged: 10),
        decide(hasTask: false),
        CaptureDecision.none,
      ]) {
        expect(d.openCamera, isFalse);
        expect(d.canShare, isFalse, reason: 'sharing without a photo');
      }
    });
  });

  test('the stored shape and the viewfinder are one number', () {
    expect(kCaptureAspect, 3 / 4);
    expect(kCaptureWidth / kCaptureHeight, closeTo(kCaptureAspect, 0.0001));
  });

  group('whether a post needs a photo', () {
    test('a session post is its photo', () {
      expect(photoRequiredToPost(isMilestone: false), isTrue);
    });
    test('a milestone stands without one', () {
      expect(photoRequiredToPost(isMilestone: true), isFalse);
    });
    test('the stop rules are unchanged by it', () {
      expect(
        decideAfterStop(loggedSeconds: 59, hasTask: true, isGuest: false,
            taskTotalSeconds: 72000, milestoneBandSeconds: 72000).openCamera,
        isFalse,
      );
      expect(
        decideAfterStop(loggedSeconds: 600, hasTask: false, isGuest: false,
            taskTotalSeconds: 72000, milestoneBandSeconds: 72000).openCamera,
        isFalse,
      );
    });
  });
}
