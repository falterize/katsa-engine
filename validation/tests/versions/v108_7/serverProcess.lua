-- A hosting player starts the game as a server process of its own, joins it with the admin token
-- and stops it again; the process also stops itself when its host leaves.
local Module = {}

local function waitFor(condition, seconds)
    local deadline = katsa.timer.getTime() + seconds
    while katsa.timer.getTime() < deadline do
        if condition() then
            return true
        end
        katsa.timer.sleep(0.05)
    end
    return condition()
end

function Module.run(self)
    local scene = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    scene:load()
    local Session = getmetatable(scene.demo).__index
    local ServerProcess, GameClient, ArenaStatics = Session.ServerProcess, Session.GameClient, Session.ArenaStatics
    if not ServerProcess.isSupported() then
        self:check(true, 'serverProcess: skipped (this platform cannot start programs)')
        scene:release()
        return
    end
    local World3D = require('source.engine.world.world')
    local port = 47700 + math.floor(os.clock() * 1000) % 200
    local server, reason = ServerProcess.start({
        scene = 'multiplayerCars',
        port = port,
        name = 'Child',
        console = false,
    })
    self:check(server ~= nil, 'a server process starts' .. tostring(reason))
    local ready = false
    waitFor(function()
        ready = server:isReady(0.05) == true
        return ready
    end, 60)
    self:check(ready and server:isRunning(), 'the server process reports that it listens')

    local world = World3D.new(scene.world.resources, nil, {
        physics = { unitsPerMeter = 1, gravity = { 0, -9.81, 0 }, backend = 'jolt' },
    })
    ArenaStatics.build({ world = world })
    local function newClient(name, token)
        return GameClient.new({}, {
            address = '127.0.0.1',
            port = port,
            name = name,
            adminToken = token,
            world = world,
            input = function()
                return { throttle = 0, steer = 0 }
            end,
        })
    end
    local function run(client, seconds)
        local frames = math.floor(seconds * 60)
        for _ = 1, frames do
            world.physics:update(1 / 60)
            client:afterPhysics()
            client:update(1 / 60)
            katsa.timer.sleep(1 / 60)
        end
    end
    local intruder = newClient('Eve')
    intruder:connect()
    run(intruder, 2)
    local client = newClient('Ann', server.token)
    client:connect()
    run(client, 2)
    self:check(client.client:isConnected(), 'the host client connects to the server process')
    self:check(client.hostId == client:getPlayerId(), 'the client that presents the token becomes the host')
    self:check(intruder.hostId ~= intruder:getPlayerId(), 'a player without the token is not the host')
    intruder:disconnect()

    -- When the host leaves, the process stops itself and removes its ready file.
    client:disconnect()
    local stopped = waitFor(function()
        return not server:isRunning()
    end, 20)
    self:check(stopped, 'the server process stops when its host leaves')
    self:check(
        not katsa.filesystem.getInfo(server.readyFile, 'file'),
        'a stopped server removes its ready file'
    )
    server:release()
    world.root:destroy()

    -- The menu's Host button: the Session starts the process, joins it and ends it again.
    local session = scene.demo
    session:host('Ann', port + 1, { console = false })
    self:check(session.mode == 'starting' and session.serverProcess ~= nil, 'hosting starts a server process')
    local playing = waitFor(function()
        scene:update(1 / 60, 1 / 60)
        return session.mode == 'playing'
    end, 60)
    self:check(playing, 'the host session joins its own server process')
    self:check(
        session.client.hostId == session.client:getPlayerId(),
        'the hosting player is the host of that server'
    )
    local child = session.serverProcess
    session:leave()
    self:check(
        waitFor(function()
            return not child:isRunning()
        end, 20),
        'leaving ends the server process'
    )
    scene:release()
end

return Module
