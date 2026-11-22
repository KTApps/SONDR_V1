import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/task.dart';
import 'tasks_repository.dart';

/// Firestore-backed [TasksRepository]. Each task is a document under
/// `users/{uid}/tasks/{taskId}` with `{ name, secondsByDay }` — the same shape
/// as the [Task] model, so the per-day pie split and milestone maths are
/// unchanged. A numeric `createdAt` preserves insertion order so a task keeps
/// its ring tone across days.
class FirestoreTasksRepository implements TasksRepository {
  FirestoreTasksRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('users').doc(uid).collection('tasks');

  @override
  Future<List<Task>> fetchAll() async {
    final snap = await _col.orderBy('createdAt').get();
    return [for (final d in snap.docs) Task.fromMap(d.id, d.data())];
  }

  @override
  Future<Task> create(String name) async {
    final ref = _col.doc();
    final task = Task(id: ref.id, name: name.trim());
    await ref.set({
      ...task.toMap(),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    return task;
  }

  /// The task document first, so the name the app reads is right the
  /// moment this returns to it; then every private photo of the task that
  /// still carries another name, at most [batchLimit] to a batch.
  ///
  /// Safe to run again: a photo already carrying [name] is left alone, so
  /// a rename cut off partway is finished by the next one.
  @override
  Future<void> rename(String taskId, String name, {int batchLimit = 450}) async {
    final value = name.trim();
    await _col.doc(taskId).update({'name': value});
    final photos = await db
        .collection('users')
        .doc(uid)
        .collection('photos')
        .where('taskId', isEqualTo: taskId)
        .get();
    final stale = [
      for (final d in photos.docs)
        if (d.data()['taskName'] != value) d.reference,
    ];
    for (var i = 0; i < stale.length; i += batchLimit) {
      final batch = db.batch();
      for (final ref in stale.skip(i).take(batchLimit)) {
        batch.update(ref, {'taskName': value});
      }
      await batch.commit();
    }
  }

  @override
  Future<void> delete(String taskId) async {
    await _col.doc(taskId).delete();
  }

  @override
  Future<void> save(Task task) async {
    // Merge so the createdAt ordering key is preserved.
    await _col.doc(task.id).set(task.toMap(), SetOptions(merge: true));
  }
}
