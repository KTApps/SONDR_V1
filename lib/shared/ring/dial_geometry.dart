import 'dart:math' as math;

/// Where each slice of the outer band begins.
///
/// Angles are measured CLOCKWISE from the ring's start (12 o'clock), so 0
/// is the top and the list is the running total around the circle. The
/// closing boundary at 2π is not included — it never moves.
///
/// The outer band is a pie of today's time, and a pie slice shrinks when
/// the pie gains filling. With the slices in task order, logging time on a
/// second task made every earlier boundary slide ANTICLOCKWISE while
/// nothing had been taken away from the task it belonged to — the ring
/// appeared to run backwards during a session.
///
/// Rotating the pie so the SELECTED slice begins at 12 fixes it, and the
/// proof is arithmetic rather than appearance. With the selected slice
/// first, the k-th boundary is the share of the first k slices, and only
/// the selected one is growing: (s+δ+a)/(T+δ) ≥ (s+a)/T whenever T ≥ s+a,
/// which it is, because T is the sum of all of them. Every boundary is
/// non-decreasing; the one at 12 is pinned.
List<double> outerSegmentStarts({
  required List<double> weights,
  required double slitAngle,
  int? selectedSegment,
}) {
  if (weights.isEmpty) return const [];
  final total = weights.fold<double>(0, (s, w) => s + w);
  if (total <= 0) return List<double>.filled(weights.length, 0);

  final available = (2 * math.pi) - (slitAngle * weights.length);
  final starts = <double>[];
  var cursor = 0.0;
  for (final weight in weights) {
    starts.add(cursor);
    cursor += (weight / total) * available + slitAngle;
  }

  final selected = selectedSegment;
  if (selected == null || selected < 0 || selected >= starts.length) {
    return starts;
  }

  // Turn the whole ring so the selected slice opens at 12, keeping every
  // slice in its existing cyclic order: the ones before it wrap round to
  // the end rather than being reordered.
  final turn = starts[selected];
  final full = 2 * math.pi;
  return [
    for (final start in starts) (start - turn + full) % full,
  ];
}

/// The shortest way round from [from] to [to], as a signed angle.
///
/// A rotation from 350° to 10° is 20° clockwise, not 340° anticlockwise.
/// Interpolating the raw numbers would spin the ring most of the way round
/// to arrive somewhere it was nearly at already.
double shortestTurn(double from, double to) {
  const full = 2 * math.pi;
  var delta = (to - from) % full;
  if (delta > math.pi) delta -= full;
  if (delta < -math.pi) delta += full;
  return delta;
}
