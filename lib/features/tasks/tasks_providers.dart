import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'firestore_tasks_repository.dart';
import 'local_tasks_repository.dart';
import 'models/task.dart';
import 'tasks_repository.dart';

/// The active [TasksRepository]. Firestore when Firebase is ready and selected,
/// otherwise the local in-memory implementation (tests, offline, init failure).
/// Nothing downstream knows or cares which one it is.
final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (kUseFirebase && ref.watch(firebaseReadyProvider) && uid != null) {
    return FirestoreTasksRepository(db: FirebaseFirestore.instance, uid: uid);
  }
  return LocalTasksRepository();
});

/// Owns the task list and the mutations the timer screen needs. Async to match
/// the eventual backend; the local repository resolves instantly so no loading
/// state is visible in practice.
class TasksController extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() {
    return ref.watch(tasksRepositoryProvider).fetchAll();
  }

  TasksRepository get _repo => ref.read(tasksRepositoryProvider);

  /// Creates a task and refreshes the list. Returns the new task.
  Future<Task> addTask(String name) async {
    final task = await _repo.create(name);
    state = AsyncData(await _repo.fetchAll());
    return task;
  }

  /// Logs [seconds] of effort against [taskId] on the day [when]. This is how a
  /// finished/paused timer session lands in a task's history.
  Future<void> logSeconds(String taskId, int seconds, DateTime when) async {
    if (seconds <= 0) return;
    final current = state.value ?? await _repo.fetchAll();
    final task = current.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;
    await _repo.save(task.addingSeconds(seconds, when));
    state = AsyncData(await _repo.fetchAll());
  }
}

final tasksProvider =
    AsyncNotifierProvider<TasksController, List<Task>>(TasksController.new);

/// The id of the explicitly selected task. **Null is the default "Task"
/// (collective overview) mode** — no specific task; the dial shows every task's
/// day-split and is view-only. A non-null id is a specific task: the centre
/// follows it and the timer controls appear. Kept independent of the task list
/// so logging time never resets it.
class SelectedTaskId extends Notifier<String?> {
  @override
  String? build() => null;

  /// Choose a specific task.
  void select(String id) => state = id;

  /// Snap back to collective "Task" mode (used by the double-tap shortcut).
  void clear() => state = null;
}

final selectedTaskIdProvider =
    NotifierProvider<SelectedTaskId, String?>(SelectedTaskId.new);

/// The specific task currently driving the centre/controls, or **null in
/// collective mode** (also null if the selected id no longer exists). No
/// fallback to the first task — null genuinely means the overview.
final selectedTaskProvider = Provider<Task?>((ref) {
  final id = ref.watch(selectedTaskIdProvider);
  if (id == null) return null;
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  return tasks.where((t) => t.id == id).firstOrNull;
});
