const std = @import("std");

/// A task with a title, description, and completion status.
const Task = struct {
    title: []const u8,
    description: []const u8,
    completed: bool,

    /// Create a new task with the given title and description.
    pub fn init(title: []const u8, description: []const u8) Task {
        return Task{
            .title = title,
            .description = description,
            .completed = false,
        };
    }

    /// Mark the task as completed.
    pub fn complete(self: *Task) void {
        self.completed = true;
    }
};

/// Manage a collection of tasks.
pub fn countCompleted(tasks: []const Task) usize {
    var count: usize = 0;
    for (tasks) |task| {
        if (task.completed) count += 1;
    }
    return count;
}
