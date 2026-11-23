import 'models/task.dart';

/// Data-access seam for tasks. The app depends only on this interface; today it
/// is backed by an in-memory implementation, and the Firebase/Firestore version
/// drops in later without any feature code changing. Methods are async to match
/// that eventual backend even though the local implementation resolves
/// instantly.
abstract interface class TasksRepository {
  /// All of the user's tasks, in display order.
  Future<List<Task>> fetchAll();

  /// Creates a new task with [name] and returns it.
  Future<Task> create(String name);

  /// Persists changes to an existing task (e.g. after logging time).
  Future<void> save(Task task);

  /// Calls [taskId] [name]. The task's own document, and the name each of
  /// its private photos carries. Posts, notices and shares still waiting to
  /// upload keep the name they were made under: they are records of what
  /// was said at the time.
  Future<void> rename(String taskId, String name);

  /// Removes the task document itself. Everything that hangs off a task —
  /// photos, collages — is someone else's to remove; see `deleteTask`.
  Future<void> delete(String taskId);
}
