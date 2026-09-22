"""
Entry point — demonstrates the task management module.

Nothing here is imported by the package itself; it is a script that shows
the store, the models and the filters working together.
"""
from pkg.filters import overdue
from pkg.models import Task, TaskStatus
from pkg.store import TaskStore


def build_store() -> TaskStore:
    """
    Builds a store seeded with a few sample tasks.

    Kept separate from ``main`` so the same seed data can be reused when
    the script is imported rather than run.
    """
    store = TaskStore()
    store.add(Task("Write docs", "Document the API endpoints"))
    store.add(Task("Fix bug #42", priority=2))
    store.add(Task.urgent("Restore the build"))
    return store


def main():
    """Creates sample tasks and displays them."""
    store = build_store()

    for task in store.list_pending():
        print(task.summary())

    for task in overdue(list(store.list_pending()), threshold=4):
        print(f"Overdue: {task.slug()}")

    store.complete("Write docs")
    print(f"Completed: {store.count_by_status(TaskStatus.DONE)}")


if __name__ == "__main__":
    main()
