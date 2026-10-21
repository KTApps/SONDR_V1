import 'collages_repository.dart';
import 'models/photo.dart';

/// What the viewer swipes through, per surface — decided here, in one
/// place, so a tap on any tile opens the same set its surface shows.

/// A stretch: what the detail displays (the collage's photos, with the
/// crossing photo added back), then every other photo of the band in
/// capture order. Nothing the stretch holds is unreachable from it.
List<Photo> bandViewerSet(BandDetail detail) {
  final shown = {for (final p in detail.photos) p.id};
  return [
    ...detail.photos,
    for (final p in detail.band)
      if (!shown.contains(p.id)) p,
  ];
}

/// A month on the Photos lens, or a day in the calendar's sheet: exactly
/// the order on screen.
List<Photo> displayedViewerSet(List<Photo> displayed) => List.of(displayed);

/// Where [photo] sits in [set] — the page to open on. A photo the set does
/// not hold opens the first page rather than nothing.
int viewerIndexOf(List<Photo> set, Photo photo) {
  final i = set.indexWhere((p) => p.id == photo.id);
  return i < 0 ? 0 : i;
}
