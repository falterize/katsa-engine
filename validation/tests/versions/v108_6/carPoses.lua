-- multiplayerCars: the drawn car, the seated player's capsule and the stand-in of another
-- player's car must match their collision wireframes at any frame time (1/144, 1/30, jitter).
local Probe = require('validation.tests.versions.v108_6.posesProbe')
local Module = {}

local function frames(self, host, count, dt, driver)
    for _ = 1, count do
        local step = dt or (1 / 200 + self:random() * (1 / 25 - 1 / 200))
        self.remote.world.physics:update(1 / 60)
        self.remote.client:afterPhysics()
        self.remote.client:update(1 / 60)
        host:update(step, step)
        host:draw()
        driver()
    end
end

function Module.run(self)
    self.stats, self.seed, self.note, self.random = {}, 4242, Probe.note, Probe.random
    local host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    host:load()
    local session = host.demo
    self.session, self.port = session, 47940 + math.floor(os.clock() * 100) % 9
    session:host('Tester', self.port, { separate = false })
    host.world.environment.debug.physics.enabled = true
    local idle = function() end
    -- The hosting player must be connected first: it becomes the host player (id order matters).
    for _ = 1, 400 do
        host:update(1 / 60, 1 / 60)
        host:draw()
        if session.mode == 'playing' then
            break
        end
    end
    self:check(session.mode == 'playing', 'hosting connects the local client')
    Probe.startRemote(self, host)
    frames(self, host, 60, 1 / 60, idle)
    session:changeCar()
    frames(self, host, 15, 1 / 60, idle)
    local hostCar = session.client:getCar()
    -- The other player takes a free car (not the host's), which the host then follows.
    for netId, car in pairs(self.remote.client.cars) do
        if netId ~= hostCar and not car.isBot then
            self.remote.client:sit(netId)
        end
    end
    frames(self, host, 50, 1 / 60, idle)
    self:check(session.client:getCar() ~= nil, 'the host player is seated in a car')
    host.input.actions.keys.up = true
    self.seated, self.remote.started, self.remote.throttle = true, true, 1
    frames(self, host, 60, 1 / 60, idle)
    local stats = self.stats
    local renderer = host.world._activeRenderer
    self:check(
        renderer and renderer.stats.frameReused == false,
        'the 3D frame is never reused while collision wireframes are drawn'
    )
    for _, case in ipairs({
        { 'at 1/144', 1 / 144, 150 },
        { 'at 1/30', 1 / 30, 60 },
        { 'with random frame times', false, 150 },
    }) do
        self.stats = {}
        frames(self, host, case[3], case[2], function()
            Probe.measure(self, host, session)
        end)
        local s = self.stats
        local label = ' ' .. case[1]
        self:check(
            s.ownCar and s.ownCar.max < 1e-3,
            'a driven car and its wireframe share the render pose' .. label
        )
        self:check(
            s.seatedCapsule and s.seatedCapsule.max < 1e-3,
            'the seated capsule stays on the car along its own up axis' .. label
        )
        self:check(
            s.followCar and s.followCar.max < 1e-3,
            'the host stand-in of another driver sits where that car is drawn' .. label
        )
        self:check(
            s.speed and s.speed.max > 0.05,
            'the car moves during the measurement'
        )
    end
    host.input.actions.keys.up = nil
    self.remote.throttle = 0
    self.remote.client:disconnect()
    host:release()
end

return Module
