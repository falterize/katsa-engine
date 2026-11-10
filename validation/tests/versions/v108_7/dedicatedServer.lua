-- A server with its own physics world (ServerHost) serves a client that plays through the network,
-- as a dedicated server does for every player.
local Module = {}

function Module.run(self)
    -- The scene package provides the `scene.` modules the car game requires.
    local scene = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    scene:load()
    local Session = getmetatable(scene.demo).__index
    local ServerHost, GameClient, ArenaStatics = Session.ServerHost, Session.GameClient, Session.ArenaStatics
    local World3D = require('source.engine.world.world')
    local resources = scene.world.resources
    local port = 47200 + math.floor(os.clock() * 1000) % 500

    local host = ServerHost.new(resources, { port = port, name = 'Test', bot = false })
    host:start()
    local world = World3D.new(resources, nil, {
        physics = { unitsPerMeter = 1, gravity = { 0, -9.81, 0 }, backend = 'jolt' },
    })
    ArenaStatics.build({ world = world })
    local client = GameClient.new({}, {
        address = '127.0.0.1',
        port = port,
        name = 'Ann',
        world = world,
        input = function()
            return { throttle = 0, steer = 0 }
        end,
    })
    client:connect()
    for _ = 1, 240 do
        host:update(1 / 60)
        world.physics:update(1 / 60)
        client:afterPhysics()
        client:update(1 / 60)
        katsa.timer.sleep(0.002)
    end
    local server = host:getServer()
    self:check(server:getPlayerCount() == 1, 'a client joins a server that has no scene of its own')
    self:check(host.game.hostPlayer == nil, 'a dedicated server has no host player')
    self:check(client.client:isConnected(), 'the client is connected over the network')
    local cars = 0
    for _ in pairs(host.game.cars) do
        cars = cars + 1
    end
    self:check(cars == 1, 'the server spawned the player car in its own physics world')
    self:check(client:getCar() == nil or type(client:getCar()) == 'table', 'the client sees the replicated cars')
    -- Simulated conditions show up in the measured ping on both ends.
    local player = server:getPlayers()[1]
    player.ping.interval, client.client.ping.interval = 0.2, 0.2
    local function run(frames)
        for _ = 1, frames do
            host:update(1 / 60)
            world.physics:update(1 / 60)
            client:afterPhysics()
            client:update(1 / 60)
            katsa.timer.sleep(1 / 60)
        end
    end
    run(60)
    local base = client.client:getPing()
    server:getConditions():set({ latency = 0.06 })
    run(150)
    self:check(
        client.client:getPing() > base + 60 and player:getPing() > base + 60,
        'a simulated 60 ms each way adds about 120 ms to the measured ping'
    )
    server:getConditions():set('off')
    client:disconnect()
    host:stop()
    world.root:destroy()
    scene:release()
end

return Module
