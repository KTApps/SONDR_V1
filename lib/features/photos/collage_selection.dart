import 'models/collage.dart';
import 'models/photo.dart';

/// One 20-hour milestone stretch, in seconds.
const int kMilestoneBandSeconds = 20 * 3600;

/// Which 20h band a photo belongs to — the ONE rule, used by the band list,
/// the collage, the task row's count and the Profile strip alike. Null when
/// the photo cannot be placed (captured before [Photo.cumulativeSeconds]
/// existed): a missing photo beats a wrong-band one.
///
/// A photo that marks a crossing ([Photo.milestoneHours] set) belongs to the
/// milestone it completed, whatever its cumulative total says — it was taken
/// seconds after the clock passed the line. Every other photo is placed by
/// its cumulative-at-capture, and the bands are closed at the top:
/// (k·20h, (k+1)·20h]. So a photo at exactly 20h00m00s completed the first
/// milestone; one second past it opened the second. Zero is band 0.
///
/// Before this the bands were half-open at the bottom, [k·20h, (k+1)·20h),
/// which put the photo taken AT the crossing into the next stretch — and
/// the row counted it while the stretch said it had no photos.
int? bandIndexOf(Photo p) {
  final hours = p.milestoneHours;
  if (hours != null && hours > 0) return hours ~/ 20 - 1;
  final cum = p.cumulativeSeconds;
  if (cum == null) return null;
  return cum <= 0 ? 0 : (cum - 1) ~/ kMilestoneBandSeconds;
}

/// The **full** set of a task's photos in a given milestone's 20h band (the
/// uncapped stretch), ordered chronologically by cumulative seconds. **Pure** —
/// no I/O — so it's unit-testable in isolation. Membership is [bandIndexOf].
///
/// This is what the collage *stores and displays* (the full mosaic);
/// [collageSelection] narrows it to the ≤9 celebration preview.
List<Photo> bandPhotos(List<Photo> taskPhotos, int milestoneHours) {
  final bandIndex = milestoneHours ~/ 20 - 1;
  return <Photo>[
    for (final p in taskPhotos)
      if (bandIndexOf(p) == bandIndex) p,
  ]..sort((a, b) => a.cumulativeSeconds!.compareTo(b.cumulativeSeconds!));
}

/// Every photo of a task that sits in a band it has REACHED — what the task
/// row counts. The same [bandIndexOf] the stretches themselves use, so the
/// count and the list can never disagree about where a photo belongs.
List<Photo> reachedBandPhotos(List<Photo> taskPhotos, int milestonesReached) {
  return <Photo>[
    for (final p in taskPhotos)
      if (bandIndexOf(p) case final b? when b < milestonesReached) p,
  ];
}

/// The one photo that stands for a milestone: the photo taken at the crossing
/// when there is one (the latest of them), else the newest photo in its band.
/// Null for a band with nothing in it.
Photo? representativePhoto(List<Photo> band, int milestoneHours) {
  if (band.isEmpty) return null;
  Photo? best;
  for (final p in band) {
    if (p.milestoneHours == milestoneHours &&
        (best == null || p.timestamp > best.timestamp)) {
      best = p;
    }
  }
  if (best != null) return best;
  for (final p in band) {
    if (best == null || p.timestamp > best.timestamp) best = p;
  }
  return best;
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

/// The crossing photo, added to what a stored collage shows — at read time,
/// so a milestone saved before the fix shows its photo without a write.
///
/// A collage is composed at the crossing, BEFORE the crossing photo is
/// captured, so it never held the photo that marks the milestone. Here any
/// photo of the band tagged with this milestone and not already shown is
/// appended, in band order. Shown photos keep their order; removed ones
/// stay removed — only the milestone's own photos are added.
List<Photo> withCrossingPhotos(
  List<Photo> shown,
  List<Photo> band,
  int milestoneHours,
) {
  final have = {for (final p in shown) p.id};
  return [
    ...shown,
    for (final p in band)
      if (p.milestoneHours == milestoneHours && !have.contains(p.id)) p,
  ];
}

/// What a stored collage's ids become once the crossing photo is saved.
///
/// Auto-composed: recomposed from the band, which now holds the crossing
/// photo (placed there by [bandIndexOf]). User-curated: the owner's picks
/// are kept exactly, and the crossing photo is appended once. A stored
/// collage is the full band, uncapped — the ≤9 is only the celebration's
/// preview, and that keeps the crossing photo by construction, as the
/// band's last — so there is never an oldest pick to drop.
List<String> attachCrossingIds(Collage collage, List<Photo> band, String crossingId) {
  if (!collage.edited) return [for (final p in band) p.id];
  if (collage.photoIds.contains(crossingId)) return collage.photoIds;
  return [...collage.photoIds, crossingId];
}
