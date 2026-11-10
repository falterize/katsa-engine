local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs

local Signals = {}

local function compact(list)
    local write = 1
    for _, connection in ipairs(list) do
        if connection.connected then
            list[write] = connection
            write = write + 1
        end
    end
    for i = #list, write, -1 do
        list[i] = nil
    end
end

function Signals.connect(self, event, callback)
    assert(not self.destroyed and not self._destroying, 'Cannot connect to a closing node')
    assert(
        type(event) == 'string' and type(callback) == 'function',
        'Events require a name and callback'
    )
    self._signals = self._signals or {}
    local list = self._signals[event]
    if not list then
        list = { depth = 0 }
        self._signals[event] = list
    end
    if list.depth == 0 then
        compact(list)
    end
    local connection = { connected = true, callback = callback }

    function connection:disconnect()
        self.connected, self.callback = false, nil
    end
    list[#list + 1] = connection
    return connection
end

-- Whether the event has at least one live connection (UI hit-testing treats such nodes as input
-- targets).
function Signals.hasConnections(self, event)
    local list = self._signals and self._signals[event]
    if list then
        for _, connection in ipairs(list) do
            if connection.connected then
                return true
            end
        end
    end
    return false
end

function Signals.emit(self, event, ...)
    local list = self._signals and self._signals[event]
    if not list then
        return
    end
    list.depth = list.depth + 1
    local firstError
    -- Newly connected callbacks wait for the next emission; disconnections
    -- take effect immediately. Nested emission has its own starting count.
    local count = #list
    for i = 1, count do
        local connection = list[i]
        if connection and connection.connected then
            local ok, message = pcall(connection.callback, ...)
            if not ok then
                firstError = firstError or message
            end
        end
    end
    list.depth = list.depth - 1
    if list.depth == 0 then
        compact(list)
    end
    if firstError then
        error(firstError, 0)
    end
end

function Signals.clear(self)
    if self._signals then
        for _, list in pairs(self._signals) do
            for _, connection in ipairs(list) do
                connection:disconnect()
            end
        end
        self._signals = nil
    end
end

return Signals
