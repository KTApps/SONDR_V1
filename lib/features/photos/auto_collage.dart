import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collages_repository.dart';
import 'photos_repository.dart';

/// Compose this milestone's collage, unasked.
///
/// A gift, zero user action: crossing twenty hours puts the band's photos
/// together whether or not anyone is looking at the celebration. Fired
/// unawaited by its callers so it never delays what is on screen, and it
/// swallows its own failures — a collage that did not compose is worth
/// nothing to interrupt anybody over, and the repository guards against
/// clobbering one the owner has edited.
///
/// Stores the FULL band (the uncapped mosaic); the ≤9 even spread is only
/// the celebration's preview.
/// The crossing photo has just been saved: put it in the milestone's
/// collage. The collage was composed at the crossing, before this photo
/// existed, so without this the photo that marks the milestone is the one
/// photo it never shows. Swallows its own failures, like the compose.
Future<void> attachCrossingPhoto(
  WidgetRef ref,
  String taskId,
  int milestoneHours,
  String photoId,
) async {
  final photos = ref.read(photosRepositoryProvider);
  final collages = ref.read(collagesRepositoryProvider);
  if (photos == null || collages == null) return;
  try {
    final band = await photos.photosForBand(taskId, milestoneHours);
    await collages.attachCrossing(taskId, milestoneHours, photoId, band);
  } catch (e) {
    debugPrint('SONDR collage attach error: $e');
  }
}

Future<void> autoComposeCollage(
  WidgetRef ref,
  String taskId,
  int milestoneHours,
) async {
  final photos = ref.read(photosRepositoryProvider);
  final collages = ref.read(collagesRepositoryProvider);
  if (photos == null || collages == null) return;
  try {
    final band = await photos.photosForBand(taskId, milestoneHours);
    await collages.saveAuto(taskId, milestoneHours, [
      for (final p in band) p.id,
    ]);
  } catch (e) {
    debugPrint('SONDR collage auto-compose error: $e');
  }
}
