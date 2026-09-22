# frozen_string_literal: true

require_relative 'task'

# Service for managing tasks — wraps an in-memory store.
#
# The store is keyed by the id the service hands out itself, so a task
# built elsewhere can never collide with one created here.
class TaskService
  # Raised when an operation names a task that is not in the store.
  #
  # Nested inside the service because the id space it complains about is
  # the service's own; a top-level MissingTask would be ambiguous.
  class MissingTask < StandardError
    # @return [Integer] the id that was not found
    attr_reader :id

    # @param id [Integer] the id that was not found
    def initialize(id)
      @id = id
    end

    # A one-line description for a log.
    # @return [String]
    def message
      "no task with id #{@id}"
    end
  end

  def initialize
    @tasks = {}
    @next_id = 1
  end

  # Adds a task with the given title and returns it.
  # @param title [String] the task title
  # @return [Task]
  def add(title)
    task = Task.new(id: @next_id, title: title)
    @tasks[@next_id] = task
    @next_id += 1
    task
  end

  # Marks a task as done by ID.
  # @param id [Integer]
  # @return [Boolean] true if found
  def complete(id)
    task = @tasks[id]
    return false unless task

    task.complete!
    true
  end

  # Marks a task as done, raising when it is not there.
  # @param id [Integer]
  # @raise [MissingTask] when no task has that id
  # @return [Task]
  def complete!(id)
    raise MissingTask.new(id) unless @tasks.key?(id)

    @tasks[id].tap(&:complete!)
  end

  # Returns all pending tasks.
  # @return [Array<Task>]
  def pending
    @tasks.values.reject(&:done?)
  end

  # Yields each pending task, or returns an enumerator without a block.
  # @return [Enumerator, nil]
  def each_pending
    return to_enum(:each_pending) unless block_given?

    pending.each { |task| yield task }
  end

  # The title of the most recently added task, if there is one.
  # @return [String, nil]
  def latest_title
    @tasks.values.last&.title
  end

  # Renders the backlog as a block of text.
  # @return [String]
  def report
    <<~REPORT
      #{self.class.name} — #{pending.length} pending
      #{pending.map { |t| "- #{t.title}" }.join("\n")}
    REPORT
  end

  alias to_s report

  # Builds a service preloaded with the given titles.
  # @param titles [Array<String>]
  # @return [TaskService]
  def self.seeded(titles)
    titles.each_with_object(new) { |title, service| service.add(title) }
  end
end
