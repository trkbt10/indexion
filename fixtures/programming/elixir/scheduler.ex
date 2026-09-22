defmodule TaskApp.Scheduler do
  @moduledoc """
  Priority scheduling for the task pipeline.

  Provides a struct, a protocol and a few guards used by the
  `TaskApp.TaskServer` process.
  """

  alias TaskApp.TaskServer
  import Enum, only: [sort_by: 2]
  require Logger

  @default_backoff 1.5

  defstruct [:name, :priority, attempts: 0, backoff: @default_backoff]

  @typedoc "How urgently a task should run."
  @type priority :: :low | :normal | :high

  @doc "Returns true when the priority is the highest level."
  defguard is_urgent(p) when p == :high

  @doc """
  Orders tasks so that high priority names come first.

  Ties keep their original relative order.
  """
  def schedule(tasks) when is_list(tasks) do
    tasks
    |> sort_by(fn %{priority: p} -> weight(p) end, :desc)
    |> Enum.map(& &1.name)
  end

  @doc "Numeric weight of a priority atom."
  def weight(:high), do: 2
  def weight(:normal), do: 1
  def weight(_other), do: 0

  @doc "Renders a policy as a human readable string."
  def describe(%__MODULE__{} = task) do
    "#{task.name}: backoff #{task.backoff}, tried #{task.attempts} time(s)"
  end

  @doc "Builds a scheduler entry, logging when the priority is urgent."
  def build(name, priority \\ :normal) do
    if is_urgent(priority) do
      Logger.warning("urgent task queued: " <> name)
    end

    %__MODULE__{name: name, priority: priority}
  end

  defp normalize(value) when is_binary(value), do: String.downcase(value)
  defp normalize(value), do: value

  @doc "Expands to a compile-time constant."
  defmacro default_backoff do
    quote do: unquote(@default_backoff)
  end
end

defprotocol TaskApp.Describable do
  @moduledoc "Anything that can render itself for a status report."

  @doc "Returns a one-line summary."
  def summary(term)
end
