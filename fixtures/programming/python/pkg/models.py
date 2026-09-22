"""
Domain models for task management.

A task is a plain dataclass: it carries no behaviour that depends on where
it is stored, so the store and the filters can be swapped freely.
"""
import functools
from enum import Enum
from dataclasses import dataclass, field


def memoized(method):
    """
    Caches a zero-argument method's result on the instance.

    Used for values that are derived from immutable fields, so recomputing
    them would always give the same answer.
    """
    attr = "_memo_" + method.__name__

    @functools.wraps(method)
    def wrapper(self):
        if not hasattr(self, attr):
            object.__setattr__(self, attr, method(self))
        return getattr(self, attr)

    return wrapper


class TaskStatus(Enum):
    """Status of a task."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    DONE = "done"


@dataclass
class Task:
    """
    A task with title, description, and status.

    Supports priority ordering — lower number means higher priority.
    """

    class Label:
        """
        A free-form tag attached to a task.

        Labels are compared by their normalized text, so "Bug" and "bug"
        are the same label.
        """

        def __init__(self, text: str) -> None:
            self.text = text

        @property
        def normalized(self) -> str:
            """The label text, lowercased and stripped."""
            return self.text.strip().lower()

        @staticmethod
        def parse(raw: str) -> list:
            """Splits a comma-separated label string into labels."""
            return [Task.Label(part) for part in raw.split(",") if part.strip()]

    title: str
    description: str = ""
    priority: int = 5
    status: TaskStatus = field(default=TaskStatus.PENDING)
    labels: list = field(default_factory=list)

    def summary(self) -> str:
        """Returns a formatted one-line summary."""
        indicator = "✓" if self.status == TaskStatus.DONE else "○"
        return f"{indicator} [{self.priority}] {self.title}"

    @memoized
    def slug(self) -> str:
        """
        A URL-safe form of the title.

        Built by a local helper so the character test stays next to the one
        loop that uses it.
        """

        def keep(ch: str) -> str:
            return ch if ch.isalnum() else "-"

        return "".join(keep(ch) for ch in self.title.lower())

    @classmethod
    def urgent(cls, title: str) -> "Task":
        """Builds a task at the highest priority."""
        return cls(title=title, priority=1)

    def complete(self) -> None:
        """Marks the task as done."""
        self.status = TaskStatus.DONE
