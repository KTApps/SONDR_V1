import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/widgets/milestone_ring.dart';

/// The ring's geometry: today's photo ring, solid.
void main() {
  const onPhoto = MilestoneRingGeometry(onPhoto: true);
  const plain = MilestoneRingGeometry(onPhoto: false);

  test('is the photo milestone card\'s ring: Ø184, 9% stroke, halo inside', () {
    expect(onPhoto.size, 184);
    expect(onPhoto.thickness, closeTo(16.56, 0.001));
    // RingDial: radius = size/2 − thickness/2 − 0.18 × thickness.
    expect(onPhoto.haloPad, closeTo(2.981, 0.001));
    expect(onPhoto.radius, closeTo(80.739, 0.001));
    expect(onPhoto.extent, closeTo(178.04, 0.01));
    expect(onPhoto.inner, closeTo(144.92, 0.01));
    // Off a photo there is no halo to keep inside.
    expect(plain.radius, closeTo(83.72, 0.001));
    expect(plain.extent, 184);
  });

  test('scales with its box, so a cover drawn at 1080 is the same ring', () {
    const big = MilestoneRingGeometry(size: 184 * 3, onPhoto: true);
    expect(big.thickness, closeTo(onPhoto.thickness * 3, 1e-9));
    expect(big.radius, closeTo(onPhoto.radius * 3, 1e-9));
    expect(big.extent, closeTo(onPhoto.extent * 3, 1e-9));
  });

  test('the glow under the band is as specified', () {
    expect(kMilestoneRingGlowOpacity, 0.22);
    expect(kMilestoneRingGlowWidth, 1.35);
    expect(kMilestoneRingGlowBlur, 10);
  });
}
