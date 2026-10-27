import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collages_repository.dart';
import 'photos_repository.dart';

/// Tell every surface that shows a photo that the photos have changed.
///
/// All of them read through one-shot FutureProviders, which fetch once and
/// then hold what they fetched. `.autoDispose` would clear a provider nobody
/// is watching — but the shell keeps all three tabs alive in an IndexedStack
/// so the running timer survives a tab switch, which means Profile is always
/// watching, so its cache was never dropped. A photo saved after the first
/// look at Profile did not appear until the process died: not a stale frame,
/// a stale read that nothing was ever going to repeat.
///
/// Explicit invalidation rather than streams, because that is what the rest
/// of the app does at a write — claiming a handle invalidates the profile,
/// editing a collage invalidates the collage list — and because photos are
/// written from exactly two places. Invalidating a family clears every
/// instance of it.
void invalidatePhotoViews(WidgetRef ref) => _invalidateAll((p) => ref.invalidate(p));

/// The same from a provider's own [Ref] — the share job, which saves a
/// photo from behind the screens.
void invalidatePhotoViewsWith(Ref ref) => _invalidateAll((p) => ref.invalidate(p));

void _invalidateAll(void Function(dynamic) invalidate) {
  // Profile: the hero emblem's newest capture, and the lifetime count.
  invalidate(galleryPreviewProvider);
  // Profile's Milestones strip, and the Milestones page.
  invalidate(collagesListProvider);
  invalidate(collagePhotosProvider);
  invalidate(bandPhotosProvider);
  invalidate(bandDetailProvider);
  invalidate(taskBandPhotosProvider);
  // History: the calendar's month grid and a day's detail sheet.
  invalidate(photosForDayProvider);
  invalidate(photosForMonthProvider);
  invalidate(earliestPhotoMonthProvider);
}
