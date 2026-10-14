import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';

/// The clamp every ring and bar draws through. Two failures it exists to stop:
/// a first session that renders as nothing, and a nearly-finished band that
/// renders as finished.
void main() {
  test('an untouched band is empty, not a sliver', () {
    expect(shownProgress(0), 0);
    expect(shownProgress(-0.1), 0);
  });

  test('any time at all shows at least the floor', () {
    // Half an hour of a 20-hour band is 2.5% — thinner than the stroke.
    expect(shownProgress(0.025), kProgressFloor);
    // One minute still registers.
    expect(shownProgress(1 / 1200), kProgressFloor);
  });

  test('the middle is drawn honestly', () {
    expect(shownProgress(0.5), 0.5);
    expect(shownProgress(0.2), 0.2);
    expect(shownProgress(0.9), 0.9);
  });

  test('nearly done never reads as done', () {
    expect(shownProgress(0.99), kProgressCeiling);
    expect(shownProgress(1), kProgressCeiling);
    expect(shownProgress(2), kProgressCeiling);
    // A visible gap always remains.
    expect(kProgressCeiling, lessThan(1));
  });

  test('there is ONE ring weight, and it does not thin with diameter', () {
    // A fixed weight, not a share of each ring's diameter. The old ratio made
    // a Ø40 band ring 2.1 against a day dial's 7 — the same component drawn
    // smaller looked like a different one.
    expect(kRingStroke, 7);
    expect(ringStroke(1), 7);
    // It scales with the SCREEN, like every other number in the app.
    expect(ringStroke(0.5), 3.5);
  });

  test('the day dials and the rings cannot drift apart', () {
    // SegmentedDial strokes its compact bands at this ratio, so a dial at its
    // reference diameter lands on exactly the ring weight.
    expect(kCompactDialStrokeRatio * kCompactDialSize, closeTo(kRingStroke, 1e-9));
    expect(kCompactDialSize * kCompactDialStrokeRatio, closeTo(7, 1e-9));
  });
}
