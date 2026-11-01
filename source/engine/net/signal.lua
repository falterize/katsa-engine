-- Minimal event list: connect(fn) returns a disconnect function; fire(...) calls every handler.
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ handlers = {} }, Signal)
end

function Signal:connect(handler)
    self.handlers[#self.handlers + 1] = handler
    return function()
        for index, item in ipairs(self.handlers) do
            if item == handler then
                table.remove(self.handlers, index)
                return
            end
        end
    end
end

function Signal:fire(...)
    -- Copy: a handler may disconnect itself while the signal fires.
    local copy = { unpack(self.handlers) }
    for _, handler in ipairs(copy) do
        handler(...)
    end
end

return Signal
