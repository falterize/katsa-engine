-- katsa.event: a FIFO of events plus the pump that moves OS events into it (love.event compatible).
local Event = {}

local queue, head, tail = {}, 1, 0
local pumpSource

-- The platform registers the function that yields OS events as tables { name, ... }.
function Event.setSource(iteratorFactory)
    pumpSource = iteratorFactory
end

function Event.push(name, ...)
    assert(type(name) == 'string', 'Event name must be a string')
    tail = tail + 1
    queue[tail] = { name, n = select('#', ...), ... }
end

function Event.pump()
    if not pumpSource then
        return
    end
    for event in pumpSource() do
        tail = tail + 1
        queue[tail] = event
    end
end

local function unpackEvent(event)
    return event[1], unpack(event, 2, event.n and event.n + 1 or #event)
end

-- Iterator over queued events: for name, a, b, c in katsa.event.poll() do ... end
function Event.poll()
    return function()
        if head > tail then
            head, tail = 1, 0
            return nil
        end
        local event = queue[head]
        queue[head] = nil
        head = head + 1
        return unpackEvent(event)
    end
end

function Event.wait()
    Event.pump()
    if head <= tail then
        return Event.poll()()
    end
    return nil
end

function Event.clear()
    queue, head, tail = {}, 1, 0
end

function Event.quit(exitStatus)
    Event.push('quit', exitStatus)
end

return Event
