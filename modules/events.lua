---@diagnostic disable: undefined-global
local Events = {}
Events.__index = Events

function Events.new(state)
    return setmetatable({
        state = state,
        handlers = {},
    }, Events)
end

function Events:on(event_id, handler)
    assert(type(event_id) == "number", "event ID must be numeric")
    assert(type(handler) == "function", "event handler must be a function")
    self.handlers[event_id] = handler
end

function Events:emit(event_id, value)
    self.state.zig.engine_emit_event(self.state.context, event_id, value or 0)
end

function Events:clear()
    self.state.zig.engine_clear_events(self.state.context)
end

function Events:poll()
    local event = self.state.event
    while self.state.zig.engine_next_event(self.state.context, event) do
        local handler = self.handlers[tonumber(event.id)]
        if handler then handler(tonumber(event.value)) end
    end
end

return Events