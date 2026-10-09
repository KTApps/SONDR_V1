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

  test('the thin stroke is 3 at the standard diameter and scales', () {
    expect(thinRingStroke(56), closeTo(3, 0.0001));
    // ~5–6% of the diameter, held at every size the thin rings appear at.
    expect(thinRingStroke(40), closeTo(40 * 3 / 56, 0.0001));
    expect(kThinRingStrokeRatio, inInclusiveRange(0.05, 0.06));
  });
}
