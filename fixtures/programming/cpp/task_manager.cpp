#include <string>
#include <vector>

/**
 * Represents a single unit of work.
 *
 * A task owns its title, so a manager can outlive whatever created it.
 */
class Task {
    int id;
    std::string title;
    bool done;
public:
    int summary() { return id; }
};

/**
 * Manages a list of tasks.
 *
 * The manager hands out ids from a counter of its own, so two tasks it
 * creates can never share one.
 */
class TaskManager {
    int next_id_;
    std::vector<Task> tasks_;

public:
    /**
     * How a manager orders the tasks it returns.
     *
     * Nested inside the manager because the orderings name this manager's
     * tasks; a bare Order at namespace scope would say less.
     */
    enum class Order {
        Insertion,
        Title,
    };

    /**
     * A snapshot of the manager at one point in time.
     *
     * Nested for the same reason as Order: it carries the manager's own id
     * space and is never built anywhere else.
     */
    struct Snapshot {
        int count;
        int next_id;

        /// True when the manager held no tasks.
        bool empty() const;
    };

    /// Adds a task and returns its new id.
    int add(std::string title);

    /// Counts the tasks that are not yet done.
    int pending_count();

    /// Captures the current contents.
    Snapshot snapshot() const;
};
