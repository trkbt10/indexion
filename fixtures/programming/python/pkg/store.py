"""In-memory task storage."""
from typing import List
from .filters import PendingFilter, overdue
from .models import Task, TaskStatus


class TaskStore:
    """Stores tasks in memory with lookup by title."""

    def __init__(self):
        self._tasks: dict[str, Task] = {}

    def add(self, task: Task) -> None:
        """Adds a task to the store."""
        self._tasks[task.title] = task

    def get(self, title: str) -> Task | None:
        """Retrieves a task by title."""
        return self._tasks.get(title)

    def complete(self, title: str) -> bool:
        """Marks a task as done. Returns False if not found."""
        task = self._tasks.get(title)
        if task is None:
            return False
        task.complete()
        return True

    def list_pending(self, limit: int | None = None) -> List[Task]:
        """
        Returns the pending tasks sorted by priority.

        ``limit`` is applied after sorting, so the tasks that survive are
        the most urgent ones rather than an arbitrary prefix.
        """
        ordered = sorted(self._tasks.values(), key=lambda t: t.priority)
        return PendingFilter(limit=limit).apply(ordered)

    def list_overdue(self, threshold: int = 3) -> List[Task]:
        """Returns the pending tasks whose priority is at or above threshold."""
        return overdue(list(self._tasks.values()), threshold=threshold)

    def count_by_status(self, status: TaskStatus) -> int:
        """Counts tasks with the given status."""
        return sum(1 for t in self._tasks.values() if t.status == status)
