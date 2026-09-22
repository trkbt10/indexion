import Foundation

/// A task with title and completion status.
public struct Task: Identifiable {
    public let id: UUID
    public var title: String
    public var done: Bool = false

    /// Returns a formatted summary.
    public func summary() -> String {
        let status = done ? "✓" : "○"
        return "\(status) \(title)"
    }
}

/// Manages tasks in memory — supports add, complete, and list.
public class TaskStore: ObservableObject {
    @Published private(set) var tasks: [Task] = []

    /// How the store orders the tasks it hands out.
    ///
    /// Nested inside the store because the cases name orderings of *this*
    /// store's tasks; a bare `Order` would read as a general concept.
    public enum Order {
        case insertion
        case title

        /// The comparator this ordering implies.
        public func isBefore(_ lhs: Task, _ rhs: Task) -> Bool {
            switch self {
            case .insertion: return false
            case .title: return lhs.title < rhs.title
            }
        }
    }

    /// Adds a new task with the given title.
    public func add(title: String) {
        tasks.append(Task(id: UUID(), title: title))
    }

    /// Marks the task with the given ID as done.
    public func complete(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].done = true
    }

    /// Returns every task in the given order.
    public func sorted(by order: Order) -> [Task] {
        tasks.sorted(by: order.isBefore)
    }

    /// Returns all pending tasks.
    public var pending: [Task] {
        tasks.filter { !$0.done }
    }
}
