package com.example.tasks.scheduling

import scala.collection.immutable.ListMap
import scala.concurrent.{ExecutionContext, Future}
import java.time.Instant

/** How urgently a task should run. */
enum Priority(val weight: Int) {
  /** Run whenever there is spare capacity. */
  case Low extends Priority(0)
  case Normal extends Priority(1)
  /** Run before anything else. */
  case High extends Priority(2)
}

/** Retry behaviour attached to a scheduled task. */
final case class RetryPolicy(
  limit: Int,
  backoff: Double
) {
  /** Renders the policy for a status report. */
  def describe: String = s"retry up to $limit times, backoff $backoff"
}

/** Anything that can report the current time. */
trait Clock {
  /** Current time, in milliseconds. */
  def now: Long

  /** Sleeps for the given number of milliseconds. */
  def sleepFor(ms: Long): Unit = ()
}

/** Wall-clock implementation backed by the system clock. */
object SystemClock extends Clock {
  override def now: Long = Instant.now().toEpochMilli
}

/** Orders and dispatches tasks by priority. */
class Scheduler(clock: Clock, policy: RetryPolicy) {
  private var queue: List[(String, Priority)] = Nil

  /** Registers a task under the given priority. */
  def submit(name: String, priority: Priority = Priority.Normal): Unit = {
    queue = (name, priority) :: queue
  }

  /** Orders tasks so that high priority names come first.
    *
    * Ties keep their original relative order.
    */
  def schedule: List[String] =
    queue.sortBy(-_._2.weight).map(_._1)

  /** Runs every queued task on the given execution context. */
  def runAll()(implicit ec: ExecutionContext): Future[List[String]] =
    Future.sequence(schedule.map(name => Future(name)))

  private def escapes: String =
    "a quote \" and a backslash \\ inside, plus a brace } that is not a closer"
}
