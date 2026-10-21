import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/sondr_prompt.dart';
import 'collages_repository.dart';
import 'models/photo.dart';
import 'photo_refresh.dart';
import 'photos_repository.dart';

/// What deleting one photo takes with it, behind one seam so the viewer and
/// the tests never touch Firestore or Storage.
///
/// Deleted: the photo's Firestore doc and its Storage binary, and its place
/// in whichever collage held it. The band drops it with the doc — a band is
/// only ever derived from the photos that exist. Kept: posts it was shared
/// into; they carry their own copies.
abstract interface class PhotoDeleter {
  /// The milestone whose collage holds the photo, if any — for the prompt.
  Future<int?> milestoneHoursOf(Photo photo);

  /// Drop the photo from any collage that holds it.
  Future<void> removeFromCollages(Photo photo);

  /// Remove the photo itself: the doc, then the binary.
  Future<void> deletePhoto(Photo photo);
}

class _FirestorePhotoDeleter implements PhotoDeleter {
  _FirestorePhotoDeleter(this.photos, this.collages);
  final PhotosRepository? photos;
  final CollagesRepository? collages;

  @override
  Future<int?> milestoneHoursOf(Photo photo) async =>
      collages?.milestoneHoursOf(photo.taskId, photo.id);
  @override
  Future<void> removeFromCollages(Photo photo) async =>
      collages?.removePhoto(photo.taskId, photo.id);
  @override
  Future<void> deletePhoto(Photo photo) async => photos?.delete(photo);
}

final photoDeleterProvider = Provider<PhotoDeleter>((ref) =>
    _FirestorePhotoDeleter(
      ref.watch(photosRepositoryProvider),
      ref.watch(collagesRepositoryProvider),
    ));

/// The confirm prompt's body: where the photo will be missed from — the
/// task's milestone when one holds it, the task alone otherwise — and what
/// cannot be undone.
///
///   "It will be removed from Piano's 20h milestone. This can't be undone."
///   "It will be removed from Piano. This can't be undone."
String deletePhotoBody(Photo photo, {required int? milestoneHours}) {
  final from = milestoneHours == null
      ? photo.taskName
      : "${photo.taskName}'s ${milestoneHours}h milestone";
  return "It will be removed from $from. This can't be undone.";
}

/// Delete [photo] everywhere it is: its collage first, so no collage is
/// ever left pointing at a doc that is gone, then the doc and its binary;
/// the photo views are told last.
Future<void> deletePhotoEverywhere(WidgetRef ref, Photo photo) async {
  final deleter = ref.read(photoDeleterProvider);
  await deleter.removeFromCollages(photo);
  await deleter.deletePhoto(photo);
  invalidatePhotoViews(ref);
}

/// Ask, then delete. Returns whether the photo went: false when the prompt
/// was cancelled or dismissed, and nothing was touched. [onDeleting] fires
/// once the answer is yes, as the deletion starts.
Future<bool> confirmDeletePhoto(
  BuildContext context,
  WidgetRef ref,
  Photo photo, {
  VoidCallback? onDeleting,
}) async {
  final deleter = ref.read(photoDeleterProvider);
  final hours = photo.milestoneHours ?? await deleter.milestoneHoursOf(photo);
  if (!context.mounted) return false;
  final yes = await showSondrConfirm(
    context,
    title: 'Delete this photo?',
    body: deletePhotoBody(photo, milestoneHours: hours),
    confirmLabel: 'Delete',
  );
  if (!yes) return false;
  onDeleting?.call();
  await deletePhotoEverywhere(ref, photo);
  return true;
}
