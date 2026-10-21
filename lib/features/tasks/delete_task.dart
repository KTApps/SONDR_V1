import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../photos/collages_repository.dart';
import '../photos/photo_refresh.dart';
import '../photos/photos_repository.dart';
import '../timer/session_store.dart';
import 'models/task.dart';
import 'tasks_providers.dart';

/// What deleting a task takes with it, behind one seam so the dialog and
/// the tests never touch Firestore or Storage.
///
/// Deleted: the task's photos (every Firestore doc and its Storage binary),
/// its collages, and the task document — and with the task, its share of
/// lifetime time and milestones, which are only ever summed from tasks.
/// Kept: posts the photos were shared into; they carry their own copies.
abstract interface class TaskPurge {
  /// How many photos the task has — for the prompt, before anything goes.
  Future<int> photoCount(String taskId);
  Future<void> deletePhotos(String taskId);
  Future<void> deleteCollages(String taskId);
}

class _FirestoreTaskPurge implements TaskPurge {
  _FirestoreTaskPurge(this.photos, this.collages);
  final PhotosRepository? photos;
  final CollagesRepository? collages;

  @override
  Future<int> photoCount(String taskId) async =>
      (await photos?.photosForTask(taskId))?.length ?? 0;
  @override
  Future<void> deletePhotos(String taskId) async =>
      photos?.deleteForTask(taskId);
  @override
  Future<void> deleteCollages(String taskId) async =>
      collages?.deleteForTask(taskId);
}

final taskPurgeProvider = Provider<TaskPurge>((ref) => _FirestoreTaskPurge(
      ref.watch(photosRepositoryProvider),
      ref.watch(collagesRepositoryProvider),
    ));

/// The confirm prompt's body. One clause per thing with a count, in this
/// order, each omitted at zero; always ending on what cannot be undone.
///
///   "3h of logged time, 1 milestone and 4 photos will be deleted. This
///   can't be undone."
String deleteTaskBody({
  required int hours,
  required int milestones,
  required int photos,
}) {
  final clauses = <String>[
    if (hours > 0) '${hours}h of logged time',
    if (milestones > 0) '$milestones ${milestones == 1 ? 'milestone' : 'milestones'}',
    if (photos > 0) '$photos ${photos == 1 ? 'photo' : 'photos'}',
  ];
  const tail = "This can't be undone.";
  if (clauses.isEmpty) return tail;
  final list = clauses.length == 1
      ? clauses.single
      : '${clauses.sublist(0, clauses.length - 1).join(', ')} and ${clauses.last}';
  return '$list will be deleted. $tail';
}

/// Delete [task] and everything under it, in an order that never leaves a
/// surface pointing at something gone: selection and session first, then
/// photos, then collages, then the task itself; the photo views are told
/// last. If it is the selected task the selection is cleared; if the stored
/// session names it, the session is cleared too.
Future<void> deleteTask(WidgetRef ref, Task task) async {
  if (ref.read(selectedTaskIdProvider) == task.id) {
    ref.read(selectedTaskIdProvider.notifier).clear();
  }
  final store = ref.read(sessionStoreProvider);
  if ((await store.read())?.taskId == task.id) await store.clear();
  final purge = ref.read(taskPurgeProvider);
  await purge.deletePhotos(task.id);
  await purge.deleteCollages(task.id);
  await ref.read(tasksProvider.notifier).deleteTask(task.id);
  invalidatePhotoViews(ref);
}
