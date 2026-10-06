import 'models/task.dart';
import 'tasks_repository.dart';

/// In-memory [TasksRepository] for local-first development. Holds tasks in a
/// list and resolves instantly. Seeded with a few tasks at varying milestone
/// progress so the dial has something real to show before persistence exists.
class LocalTasksRepository implements TasksRepository {
  LocalTasksRepository() {
    _seed();
  }

  final List<Task> _tasks = [];
  int _idCounter = 0;

  void _seed() {
    // Spanish sits mid-climb toward its first 20h milestone (≈13h total, with
    // some logged today); Piano earlier; Golf has just passed 20h.
    _tasks.addAll([
      Task(
        id: _nextId(),
        name: 'Spanish',
        secondsByDay: {
          _daysAgo(9): 3 * 3600,
          _daysAgo(6): 4 * 3600,
          _daysAgo(2): 3 * 3600 + 1800,
          _today(): 2 * 3600 + 900, // 2h 15m today
        },
      ),
      Task(
        id: _nextId(),
        name: 'Piano',
        secondsByDay: {
          _daysAgo(8): 2 * 3600,
          _daysAgo(3): 2 * 3600 + 1800,
          _today(): 1800,
        },
      ),
      Task(
        id: _nextId(),
        name: 'Golf',
        secondsByDay: {
          _daysAgo(20): 12 * 3600,
          _daysAgo(5): 8 * 3600 + 600,
        },
      ),
    ]);
  }

  String _nextId() => 'task_${_idCounter++}';

  @override
  Future<List<Task>> fetchAll() async => List.unmodifiable(_tasks);

  @override
  Future<Task> create(String name) async {
    final task = Task(id: _nextId(), name: name.trim());
    _tasks.add(task);
    return task;
  }

  @override
  Future<void> save(Task task) async {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) {
      _tasks.add(task);
    } else {
      _tasks[i] = task;
    }
  }

  // --- Seed-date helpers (relative keys, computed once at construction). ---

  static String _today() => _key(DateTime.now());

  static String _daysAgo(int n) =>
      _key(DateTime.now().subtract(Duration(days: n)));

  static String _key(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
