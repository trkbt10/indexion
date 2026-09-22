"""
Status-based filtering.

Lives one package below the models it filters, so it reaches them with a
two-dot relative import.
"""
from ..models import Task, TaskStatus


class PendingFilter:
    """
    Keeps only the tasks that are still pending.

    ``limit`` caps how many survive; ``None`` keeps all of them.
    """

    class Stats:
        """How a single filter run went."""

        def __init__(self, seen: int = 0, kept: int = 0) -> None:
            self.seen = seen
            self.kept = kept

        @property
        def dropped(self) -> int:
            """How many tasks the run discarded."""
            return self.seen - self.kept

    def __init__(self, limit: int | None = None) -> None:
        self.limit = limit
        self.stats = PendingFilter.Stats()

    def apply(self, tasks: list) -> list:
        """
        Returns the pending tasks, at most ``limit`` of them.

        The per-task test is a local function so the loop reads as one
        statement and the test is not part of the public surface.
        """

        def keep(task: Task) -> bool:
            return task.status == TaskStatus.PENDING

        kept = [t for t in tasks if keep(t)]
        if self.limit is not None:
            kept = kept[: self.limit]
        self.stats = PendingFilter.Stats(seen=len(tasks), kept=len(kept))
        return kept


def overdue(tasks: list, threshold: int = 3) -> list:
    """Returns the pending tasks whose priority is at or above ``threshold``."""
    return [t for t in tasks if t.status == TaskStatus.PENDING and t.priority >= threshold]
