package com.example.tasks

import scala.collection.mutable

/** Status of a task. */
sealed trait TaskStatus
object TaskStatus {
  case object Pending extends TaskStatus
  case object Done extends TaskStatus
}

/**
 * A task with title and status.
 * @param id unique identifier
 * @param title short summary
 */
case class Task(id: Long, title: String, status: TaskStatus = TaskStatus.Pending) {
  /** Returns a formatted summary. */
  def summary: String = {
    val indicator = status match {
      case TaskStatus.Done => "✓"
      case _ => "○"
    }
    s"$indicator [$id] $title"
  }
}

/**
 * In-memory task service.
 *
 * The store is keyed by the id the service itself hands out, so a task
 * created elsewhere cannot collide with one created here.
 */
class TaskService {
  private val store = mutable.Map.empty[Long, Task]
  private var nextId = 1L

  /**
   * What one call to `complete` did.
   *
   * Nested in the service because the outcome only makes sense against
   * this service's store; a top-level `Outcome` would say nothing.
   */
  sealed trait Outcome {
    /** A one-word name for logs. */
    def label: String
  }

  /** The task was found and is now done. */
  case class Completed(task: Task) extends Outcome {
    def label: String = "completed"
  }

  /** Creates a new task. */
  def create(title: String): Task = {
    val task = Task(nextId, title)
    store(nextId) = task
    nextId += 1
    task
  }

  /** Marks a task as done. */
  def complete(id: Long): Option[Task] = {
    store.get(id).map { task =>
      val updated = task.copy(status = TaskStatus.Done)
      store(id) = updated
      updated
    }
  }

  /** Marks a task as done and reports what happened. */
  def completeReporting(id: Long): Option[Outcome] =
    complete(id).map(Completed.apply)

  /** Returns all pending tasks. */
  def pending: List[Task] =
    store.values.filter(_.status == TaskStatus.Pending).toList
}
