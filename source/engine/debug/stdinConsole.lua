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

-- The worker reads descriptor 0 with the C library's read(), not io.read: a blocked io.read holds
-- the stdin stream's lock, and exit() then waits for that lock forever, so a server with an open
-- terminal could never quit.
local SCRIPT = [[
Actor.manual = true
local ffi = require('ffi')
local read
if ffi.os == 'Windows' then
    ffi.cdef('int _read(int fd, void *buffer, unsigned int count);')
    read = ffi.C._read
else
    ffi.cdef('long read(int fd, void *buffer, unsigned long count);')
    read = ffi.C.read
end
local buffer = ffi.new('char[512]')
local pending = ''
while not Actor.stopped() do
    local count = tonumber(read(0, buffer, 512))
    if count <= 0 then
        break
    end
    pending = pending .. ffi.string(buffer, count)
    while true do
        local line, rest = pending:match('^([^\n]*)\n(.*)$')
        if not line then
            break
        end
        pending = rest
        Actor.send('line', line)
    end
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
