/// A saturation colour matrix for `ColorFilter.matrix`. [s] = 1 leaves colour
/// unchanged, 0 is full greyscale.
///
/// Shared *mechanism* only — the photo surfaces each pass their OWN strength and
/// pair it with their own flat dark tint: the calendar mutes heavily (≈0.32 +
/// ~62% black), day-detail and the profile gallery stay near-raw (≈0.85 + ~10%
/// black). This helper does not unify those values, just the maths.
List<double> saturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final ir = (1 - s) * r, ig = (1 - s) * g, ib = (1 - s) * b;
  return [
    ir + s, ig, ib, 0, 0,
    ir, ig + s, ib, 0, 0,
    ir, ig, ib + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
