import 'models/photo.dart';

/// One 20-hour milestone stretch, in seconds.
const int kMilestoneBandSeconds = 20 * 3600;

/// The **full** set of a task's photos in a given milestone's 20h band (the
/// uncapped stretch), ordered chronologically by cumulative seconds. **Pure** —
/// no I/O — so it's unit-testable in isolation.
///
/// The locked window: a photo is eligible only if its cumulative-at-capture
/// falls in *this* milestone's own 20h band — band index `milestoneHours/20 - 1`
/// (so the 20h collage is band 0 = [0,20h), the 40h collage is band 1 =
/// [20h,40h), …). Photos with a null [Photo.cumulativeSeconds] are unassignable
/// and excluded entirely (a missing photo beats a wrong-band one).
///
/// This is what the collage *stores and displays* (the full mosaic);
/// [collageSelection] narrows it to the ≤9 celebration preview.
List<Photo> bandPhotos(List<Photo> taskPhotos, int milestoneHours) {
  final bandIndex = milestoneHours ~/ 20 - 1;
  return <Photo>[
    for (final p in taskPhotos)
      if (p.cumulativeSeconds != null &&
          p.cumulativeSeconds! ~/ kMilestoneBandSeconds == bandIndex)
        p,
  ]..sort((a, b) => a.cumulativeSeconds!.compareTo(b.cumulativeSeconds!));
}

/// The ≤9 collage *preview* for a milestone — [bandPhotos] as-is when the band
/// holds 9 or fewer, otherwise exactly 9 picked: always the first and last, with
/// the middle sampled evenly across the stretch, preserving chronological order.
/// Backs the milestone celebration's bounded reveal.
List<Photo> collageSelection(List<Photo> taskPhotos, int milestoneHours) {
  final band = bandPhotos(taskPhotos, milestoneHours);
  if (band.length <= 9) return band;

  // Sample 9 indices across [0, M-1]: round(i * (M-1) / 8) for i in 0..8. This
  // always yields index 0 and M-1 (first and last), spreads the middle evenly,
  // and stays ascending → chronological. Dedupe guards a rare rounding collision
  // (can't happen for M > 9, where the step exceeds 1, but belt-and-braces).
  final last = band.length - 1;
  final picked = <Photo>[];
  final seen = <int>{};
  for (var i = 0; i < 9; i++) {
    final idx = (i * last / 8).round();
    if (seen.add(idx)) picked.add(band[idx]);
  }
  return picked;
}
