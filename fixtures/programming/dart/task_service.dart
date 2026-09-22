import 'package:example/models/task.dart';

/// How a service orders the tasks it hands out.
enum TaskOrder {
  /// Keep the order tasks were created in.
  insertion,

  /// Sort alphabetically by title.
  title;

  /// The comparator this ordering implies.
  int Function(Task, Task) get comparator => switch (this) {
        TaskOrder.insertion => (a, b) => a.id.compareTo(b.id),
        TaskOrder.title => (a, b) => a.title.compareTo(b.title),
      };
}

/// Service for managing tasks — coordinates between UI and storage.
///
/// The service owns the only mutable list of tasks in the app; everything
/// it hands out is a fresh list, so a caller cannot mutate the store by
/// accident.
class TaskService {
  final List<Task> _tasks = [];
  int _nextId = 1;

  /// Creates a new task and returns it.
  Task create(String title, {String description = ''}) {
    final task = Task(
      id: _nextId++,
      title: title,
      description: description,
    );
    _tasks.add(task);
    return task;
  }

  /// Marks a task as done by ID. Returns false if not found.
  bool complete(int id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return false;
    _tasks[index] = _tasks[index].copyWith(done: true);
    return true;
  }

  /// Returns every task in the given order.
  ///
  /// The comparison is wrapped in a local function so the null handling
  /// stays next to the single sort that needs it.
  List<Task> sorted(TaskOrder order) {
    int compare(Task a, Task b) => order.comparator(a, b);

    final copy = List<Task>.from(_tasks);
    copy.sort(compare);
    return copy;
  }

  /// Returns all pending tasks sorted by creation order.
  List<Task> get pending =>
      _tasks.where((t) => !t.done).toList();
}
