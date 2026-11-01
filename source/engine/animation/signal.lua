-- Uses the node dispatch contract: safe disconnects and nested dispatch.
local Dispatch = require('source.engine.nodes.core.signals')

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({}, Signal)
end

function Signal:connect(callback)
    return Dispatch.connect(self, 'event', callback)
end

function Signal:emit(...)
    return Dispatch.emit(self, 'event', ...)
end

function Signal:release()
    Dispatch.clear(self)
end

return Signal
