package com.example.tasks

import kotlinx.coroutines.flow.Flow

/**
 * Repository for task persistence — abstracts storage backend.
 */
interface TaskRepository {
    suspend fun getById(id: Long): Task?
    suspend fun save(task: Task): Task
    fun findAll(): Flow<Task>
}

/** In-memory implementation of [TaskRepository]. */
class InMemoryTaskRepository : TaskRepository {
    private val store = mutableMapOf<Long, Task>()
    private var nextId = 1L

    /**
     * A snapshot of the repository at one point in time.
     *
     * Nested because it is only ever produced by this repository, and
     * carries the same identity space as the store it came from.
     */
    data class Snapshot(val taken: Long, val tasks: List<Task>) {
        /** Whether the snapshot recorded no tasks at all. */
        fun isEmpty(): Boolean = tasks.isEmpty()
    }

    override suspend fun getById(id: Long): Task? = store[id]

    override suspend fun save(task: Task): Task {
        val saved = if (task.id == 0L) task.copy(id = nextId++) else task
        store[saved.id] = saved
        return saved
    }

    /** Captures the current contents as a [Snapshot]. */
    fun snapshot(): Snapshot = Snapshot(nextId, store.values.toList())

    override fun findAll(): Flow<Task> = kotlinx.coroutines.flow.flow {
        store.values.forEach { emit(it) }
    }
}
