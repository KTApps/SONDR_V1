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

  @override
  Future<void> save(Task task) async {
    // Merge so the createdAt ordering key is preserved.
    await _col.doc(task.id).set(task.toMap(), SetOptions(merge: true));
  }
}
