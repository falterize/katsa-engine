-- Diagnostic: how fast a car accelerates in the server's own physics world (full throttle on the
-- flat arena), compared with the configured acceleration. Run: --test-v108.9.cars.accel
local Previous = require('validation.tests.versions.v107.physics2D')
local Module = setmetatable({}, { __index = Previous })
Module.__index = Module
Module.scale = 1

function Module.new(manager)
    return setmetatable(Previous.new(manager), Module)
end

function Module:update() end

function Module:draw()
    if self.done then
        return
    end
    self.done = true
    Module.run(self)
    print('PASSED probe')
    katsa.event.quit()
end

function Module.run(self)
    local scene = require('game.runtime.application').new(self.manager, 'multiplayerCars')
    scene:load()
    local Session = getmetatable(scene.demo).__index
    local host = Session.ServerHost.new(scene.world.resources, { port = 47900 + math.floor(os.clock() * 1000) % 90, name = 'Probe', bot = false })
    host:start()
    local game = host.game
    local model, netId = game:spawnCar({ x = 0, z = -40, heading = 0 })
    model.getDriver = function()
        return 1
    end
    local body = game.bodies[netId]
    local config = model.config
    print(('CONFIG acceleration=%s maxSpeed=%s brake=%s'):format(config.acceleration, config.maxSpeed, config.brake))
    local elapsed, steps = 0, 0
    local marks = { [0.5] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true }
    local start = body.model.z
    for frame = 1, 60 * 7 do
        model.input = { throttle = 1 }
        host:update(1 / 60)
        elapsed = elapsed + 1 / 60
        steps = steps + (host.world.physics.stats.steps or 0)
        for mark in pairs(marks) do
            if elapsed >= mark and marks[mark] then
                marks[mark] = nil
                print(('ACCEL t=%.1fs speed=%.2f m/s (%.0f km/h) travelled=%.1f m physicsSteps=%d'):format(mark, model.speed, model.speed * 3.6, model.z - start, steps))
            end
        end
    end
    host:stop()
    Module.runClient(self, scene)
    self:check(steps == 60 * 7, 'the server world steps exactly once per 1/60 s of frame time')
end

-- The same in the player's own process: the hosted server and the client simulate in two worlds.
function Module.runClient(self, scene, keepScale)
    local host = scene
    local session = host.demo
    session:host('Tester', 47990 + math.floor(os.clock() * 100) % 9, { separate = false })
    session.server.game.bot.sightRadius = 0
    local frames = 0
    local function frame()
        frames = frames + 1
        host:update(Module.scale / 60, Module.scale / 60)
        host:draw()
    end
    for _ = 1, 150 do
        frame()
    end
    session:changeCar()
    for _ = 1, 30 do
        frame()
    end
    local carId = session.client:getCar()
    local car = carId and session.client.cars[carId]
    print('SEATED', car ~= nil)
    if not car then
        return
    end
    if not keepScale then
        Module.scale = tonumber(os.getenv('KATSA_SCALE') or 1)
    end
    session.client.input = function()
        return { throttle = 1 }
    end
    -- A parked dummy car some metres ahead of the player's car, simulated by the server.
    local heading = math.rad(car.heading)
    local dummyModel, dummyId = session.server.game:spawnCar({
        x = car.x + math.sin(heading) * 14,
        z = car.z + math.cos(heading) * 14,
        heading = car.heading,
    })
    dummyModel.getDriver = function()
        return nil
    end
    local dummy = session.server.game.bodies[dummyId]
    local clientPhysics, serverPhysics = host.world.physics, session.server.world.physics
    local c0, s0, elapsed = 0, 0, 0
    local marks = { [0.5] = true, [1] = true, [2] = true }
    local z0, x0, peak, approach, hit = car.z, car.x, 0, 0, false
    for _ = 1, 60 * 5 do
        frame()
        elapsed = elapsed + Module.scale / 60
        local dv = dummy.node.physics:getVelocity({})
        local speedDummy = math.sqrt(dv[1] ^ 2 + dv[3] ^ 2)
        peak = math.max(peak, speedDummy)
        approach = math.max(approach, car.speed)
        if speedDummy > 0.5 and not hit then
            hit = true
            print(('HIT t=%.2f playerSpeedBefore=%.2f dummySpeed=%.2f'):format(elapsed, approach, speedDummy))
        end
        c0 = c0 + (clientPhysics.stats.steps or 0)
        s0 = s0 + (serverPhysics.stats.steps or 0)
        for mark in pairs(marks) do
            if elapsed >= mark and marks[mark] then
                marks[mark] = nil
                print(('PEAK dummySpeed=%.2f playerTop=%.2f'):format(peak, approach))
                print(('CLIENT t=%.1fs speed=%.2f m/s travelled=%.1f m clientSteps=%d serverSteps=%d frames=%d'):format(mark, car.speed, math.sqrt((car.z - z0) ^ 2 + (car.x - x0) ^ 2), c0, s0, math.floor(elapsed * 60 + 0.5)))
            end
        end
    end
    return peak
end

-- Focused check: a car rammed at four times the real speed (a client running at time scale 4)
-- must not be sent flying; unfixed it left at 28 m/s.
function Module.runPush(self)
    local scene = require('game.runtime.application').new(self.manager, 'multiplayerCars')
    scene:load()
    Module.scale = 4
    local peak = Module.runClient(self, scene, true)
    Module.scale = 1
    self:check(peak and peak < 12, 'A car hit by a stand-in car at time scale 4 is not launched (peak ' .. tostring(peak) .. ' m/s)')
end

return Module
