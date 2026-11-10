-- Reads command lines from the process's standard input without blocking the frame: a worker
-- thread waits in io.read and hands every line over. Used by dedicated servers.
--
--   local console = StdinConsole.new(function(line) print('typed', line) end)
--   -- every frame:
--   console:update()
--   console:close()
--
-- Without worker threads (`katsa.thread` unavailable) `new` returns nil and a reason.
local Thread = require('source.katsa.thread')

local StdinConsole = {}
StdinConsole.__index = StdinConsole

local SCRIPT = [[
Actor.manual = true
while not Actor.stopped() do
    local line = io.read('*l')
    if not line then
        break
    end
    Actor.send('line', line)
end
Actor.send('closed', true)
]]

function StdinConsole.new(onLine)
    if not Thread.isSupported() then
        return nil, 'worker threads are unavailable'
    end
    local worker = Thread.spawn({ script = SCRIPT, name = 'stdin' })
    local self = setmetatable({ worker = worker, closed = false }, StdinConsole)
    worker:on('line', function(line)
        onLine((line:gsub('\r$', '')))
    end)
    worker:on('closed', function()
        self.closed = true
    end)
    return self
end

-- True once standard input reached its end (a service started without a terminal).
function StdinConsole:isClosed()
    return self.closed
end

function StdinConsole:update()
    self.worker:poll()
end

function StdinConsole:close()
    if self.worker then
        -- The worker may sit in a blocking read; it ends with the process.
        pcall(self.worker.stop, self.worker, 0)
        self.worker = nil
    end
end

return StdinConsole
