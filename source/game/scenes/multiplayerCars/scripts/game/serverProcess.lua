-- The hosting player's dedicated server in a process of its own, with its own console window.
--
--   local server = ServerProcess.start({ port = 7777, name = 'Ann', maxPlayers = 8 })
--   -- every frame until it listens:
--   if server:isReady() then client:connect(...) end
--   server:release() -- when the game closes: ends the process if it is still running
--
-- The server stops itself when its host (the client presenting `server.token`) leaves.
local Dedicated = require('../../server.scripts.dedicated')

local ServerProcess = {}
ServerProcess.__index = ServerProcess

local READY_TIMEOUT = 25 -- seconds to wait for the server to listen

-- 128 random bits as hex: the system's source where there is one, the clock and math.random where
-- not. It only has to stop another player on the network from claiming the host role.
local function newToken()
    local file = io.open('/dev/urandom', 'rb')
    if file then
        local bytes = file:read(16)
        file:close()
        if bytes and #bytes == 16 then
            return (bytes:gsub('.', function(char)
                return ('%02x'):format(char:byte())
            end))
        end
    end
    math.randomseed(os.time() + math.floor(os.clock() * 1e6))
    local parts = {}
    for index = 1, 4 do
        parts[index] = ('%08x'):format(math.random(0, 0xffffffff))
    end
    return table.concat(parts)
end

function ServerProcess.isSupported()
    return katsa.process.isSupported() and katsa.process.getLaunchCommand() ~= nil
end

-- options: scene (this scene's id), port, name, maxPlayers, console (default true), extra (more game arguments, e.g. the
-- --sim-* options). Returns the handle, or nil and a reason.
function ServerProcess.start(options)
    if not ServerProcess.isSupported() then
        return nil, 'This platform cannot start a server process'
    end
    local token = newToken()
    local arguments = {
        '--scene', options.scene,
        '--server', tostring(options.port),
        '--name', options.name,
        '--max-players', tostring(options.maxPlayers or 8),
        '--admin-token', token,
        '--close-with-host',
    }
    for _, value in ipairs(options.extra or {}) do
        arguments[#arguments + 1] = value
    end
    local readyFile = Dedicated.getReadyFile(options.port)
    katsa.filesystem.remove(readyFile) -- a leftover from an earlier run must not count
    local child, reason = katsa.process.spawn({
        command = katsa.process.getLaunchCommand(arguments),
        console = options.console ~= false,
        log = katsa.filesystem.getSaveDirectory() .. '/server-' .. options.port .. '.log',
    })
    if not child then
        return nil, reason
    end
    return setmetatable({
        child = child,
        token = token,
        port = options.port,
        readyFile = readyFile,
        waited = 0,
    }, ServerProcess)
end

-- True once the server listens. nil, reason when it died or took too long.
function ServerProcess:isReady(dt)
    if katsa.filesystem.getInfo(self.readyFile, 'file') then
        return true
    end
    self.waited = self.waited + (dt or 0)
    if not self.child:isRunning() then
        return nil, 'The server process stopped while starting (see its console or server-' .. self.port .. '.log)'
    elseif self.waited > READY_TIMEOUT then
        return nil, 'The server process did not start listening in time'
    end
    return false
end

function ServerProcess:isRunning()
    return self.child:isRunning()
end

-- Ends the process if it is still running (it normally stops itself when the host leaves).
function ServerProcess:release()
    self.child:kill()
end

return ServerProcess
