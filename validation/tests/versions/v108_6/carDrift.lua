-- multiplayerCars: Space brakes and drifts (smoke and skid marks while the rear tires slide), and a
-- car on its roof rights itself instead of respawning.
local Module = {}

local function frames(host, count, each)
    for index = 1, count do
        host:update(1 / 60, 1 / 60)
        -- Software GL makes a frame cost ~250 ms; the logic only needs an occasional draw.
        if index % 8 == 0 or index == count then
            host:draw()
        end
        if each then
            each()
        end
    end
end

local function countMarks(world)
    local count = 0
    for _, node in ipairs(world.ribbons and world.ribbons.nodes or {}) do
        if tostring(node.name):match('^Skid') then
            count = count + 1
        end
    end
    return count
end

function Module.run(self)
    local host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    host:load()
    local session = host.demo
    session:host('Tester', 47930 + math.floor(os.clock() * 100) % 9)
    for _ = 1, 400 do
        frames(host, 1)
        if session.mode == 'playing' then
            break
        end
    end
    frames(host, 60)
    session:changeCar()
    frames(host, 30)
    local netId = session.client:getCar()
    self:check(netId ~= nil, 'the player sits in a car')
    local body, view = session.server.bodies[netId], session.views[netId]
    local car = session.client.cars[netId]
    local keys = host.input.actions.keys
    keys.up = true
    frames(host, 100) -- the arena wall is ~170 frames away: stay clear of it
    local before = car.speed
    self:check(before > 8, 'the car accelerates before the handbrake')
    self:check((car.drift or 0) < 0.2, 'no drift while driving straight')
    keys.space = true
    keys.right = true
    local peak, smoke, marks = 0, 0, 0
    frames(host, 60, function()
        peak = math.max(peak, car.drift or 0)
        for _, emitter in pairs(view.skid.smoke) do
            smoke = math.max(smoke, emitter.rate or 0)
        end
        marks = math.max(marks, countMarks(host.world))
    end)
    self:check(peak > 0.4, 'the handbrake makes the rear tires slide (drift ' .. ('%.2f'):format(peak) .. ')')
    self:check(smoke > 0, 'smoke is emitted from the rear wheels while drifting')
    self:check(marks >= 1, 'a skid mark trail follows a sliding rear wheel')
    keys.space, keys.right, keys.up = nil, nil, nil
    frames(host, 240)
    self:check((car.drift or 0) < 0.15, 'the drift ends after the handbrake is released')
    -- Automatic flip: turned onto its roof, the car rolls back onto its wheels in place.
    local node = body.node
    local px, _, pz = body:pose()
    node.position = { px, node.position[2] + 1.5, pz }
    node.rotation = { 0, 0, 180 }
    node.body:sync()
    local ok = true
    frames(host, 60 * 8, function()
        ok = ok and not body:needsReset(1 / 60)
    end)
    local up = body.axes.up
    self:check(up[2] > 0.7, 'a car on its roof rights itself (up.y ' .. ('%.2f'):format(up[2]) .. ')')
    self:check(ok, 'a flipped car is not respawned')
    local ex, _, ez = body:pose()
    self:check(math.abs(ex - px) + math.abs(ez - pz) < 12, 'the flip happens in place')
    host:release()
end

return Module
