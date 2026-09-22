"""
Scheduling primitives for the task pipeline.

Builds on `TaskStore` and adds priority ordering and retry policies.
"""
module Scheduler

using Base.Threads
using Dates: DateTime, now
import Printf

export Priority, RetryPolicy, schedule, next_slot, @timed_run

"""Supertype of every scheduling priority."""
abstract type Priority end

struct Low <: Priority end
struct Normal <: Priority end
struct High <: Priority end

const DEFAULT_BACKOFF = 1.5

"""
    RetryPolicy(limit, backoff)

Retry behaviour attached to a scheduled task.
"""
mutable struct RetryPolicy
    limit::Int
    backoff::Float64
    attempts::Int
    RetryPolicy(limit, backoff = DEFAULT_BACKOFF) = new(limit, backoff, 0)
end

"""A slot is a millisecond offset from the epoch."""
struct Slot{T<:Integer}
    value::T
end

"""Numeric weight of a priority."""
weight(::Low) = 0
weight(::Normal) = 1
weight(::High) = 2

"""
Order tasks so that high priority names come first.

Ties keep their original relative order, because `sort` is stable.
"""
function schedule(tasks::Vector{Tuple{String,Priority}})::Vector{String}
    ordered = sort(tasks; by = t -> -weight(t[2]))
    return [name for (name, _) in ordered]
end

"""Compute the slot following `s`, spaced by the policy backoff."""
function next_slot(policy::RetryPolicy, s::Slot{T}) where {T<:Integer}
    step = ceil(T, policy.backoff * 1000)
    return Slot{T}(s.value + max(one(T), step))
end

"""Render a policy for a status report."""
function describe(p::RetryPolicy)
    return Printf.@sprintf("retry up to %d times, backoff %.2f", p.limit, p.backoff)
end

"""Time a block and report how long it took."""
macro timed_run(expr)
    return quote
        local t0 = time_ns()
        local result = $(esc(expr))
        (result, time_ns() - t0)
    end
end

end # module Scheduler
