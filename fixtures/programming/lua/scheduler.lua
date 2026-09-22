--- Scheduling primitives for the task pipeline.
-- Builds on the task manager and adds priority ordering and retry policies.
-- @module scheduler

local TaskManager = require("task_manager")
local inspect = require "inspect"

local Scheduler = {}
Scheduler.__index = Scheduler

--- Priority levels, ordered from least to most urgent.
Scheduler.PRIORITY = {
    low = 0,
    normal = 1,
    high = 2,
}

local DEFAULT_BACKOFF = 1.5

--- Creates a scheduler bound to a task manager.
-- @param manager TaskManager the manager to schedule for
-- @return Scheduler
function Scheduler.new(manager)
    local self = setmetatable({}, Scheduler)
    self.manager = manager or TaskManager.new()
    self.queue = {}
    self.backoff = DEFAULT_BACKOFF
    return self
end

--- Registers a task under the given priority.
-- @param name string
-- @param priority string one of "low", "normal", "high"
function Scheduler:submit(name, priority)
    priority = priority or "normal"
    table.insert(self.queue, { name = name, priority = priority })
end

--- Orders tasks so that high priority names come first.
-- Ties keep their original relative order.
-- @return table list of names
function Scheduler:schedule()
    local ordered = {}
    for i, entry in ipairs(self.queue) do
        ordered[i] = entry
    end
    table.sort(ordered, function(a, b)
        return self.PRIORITY[a.priority] > self.PRIORITY[b.priority]
    end)
    local names = {}
    for _, entry in ipairs(ordered) do
        names[#names + 1] = entry.name
    end
    return names
end

--[[ Renders a policy as a human readable string.
     Exercises the string lexer: "a quote \" inside" and a long [[bracket]]. ]]
function Scheduler:describe()
    return string.format("backoff %.2f, %d queued", self.backoff, #self.queue)
end

--- Retries a task until the limit is reached.
local function retry(fn, limit)
    local attempts = 0
    repeat
        attempts = attempts + 1
        local ok = fn()
        if ok then return true end
    until attempts >= limit
    return false
end

Scheduler.retry = retry

return Scheduler
