-- Diagnostic (not a pass/fail suite): measures, per frame and with variable frame times, how far
-- the drawn car model, the drawn walker and the physics debug poses are apart in multiplayerCars.
--   xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.6.poses
-- Prints one summary line per phase: metric = mean / max error in metres over the phase.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local PHASES = {
    { name = 'foot 1/60', dt = 1 / 60, frames = 60, mode = 'foot' },
    { name = 'foot 1/144', dt = 1 / 144, frames = 120, mode = 'foot' },
    { name = 'foot 1/30', dt = 1 / 30, frames = 60, mode = 'foot' },
    { name = 'drive 1/60', dt = 1 / 60, frames = 120, mode = 'drive' },
    { name = 'drive 1/144', dt = 1 / 144, frames = 240, mode = 'drive' },
    { name = 'drive 1/30', dt = 1 / 30, frames = 90, mode = 'drive' },
    { name = 'drive jitter', dt = false, frames = 240, mode = 'drive' },
}

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame, self.phase, self.phaseFrame, self.stats = 0, 1, 0, {}
    self.seed = 12345
    return self
end

function Tests:update() end

function Tests:random()
    self.seed = (self.seed * 1103515245 + 12345) % 2147483648
    return self.seed / 2147483648
end

local function distance(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

function Tests:note(name, value)
    local stat = self.stats[name]
    if not stat then
        stat = { sum = 0, max = 0, count = 0 }
        self.stats[name] = stat
    end
    stat.sum, stat.count, stat.max = stat.sum + value, stat.count + 1, math.max(stat.max, value)
end

local function entryFor(poses, raw)
    for _, entry in ipairs(poses or {}) do
        if entry.raw == raw then
            return { entry.x, entry.y, entry.z, entry }
        end
    end
end

-- Where the model node of a car puts the chassis centre (root origin raised along its own up).
local function chassisOfView(view, drop)
    local m = view.root:getWorldMatrix()
    return { m[4] + m[2] * drop, m[8] + m[6] * drop, m[12] + m[10] * drop }, { m[2], m[6], m[10] }
end

function Tests:startRemote(host)
    local World3D = require('source.engine.world.world')
    local world = World3D.new(host.world.resources, nil, {
        physics = { unitsPerMeter = 1, gravity = { 0, -9.81, 0 }, backend = 'jolt' },
    })
    local Session = getmetatable(self.session).__index
    Session.ArenaView.buildPhysics({ world = world })
    local remote = { world = world, throttle = 0 }
    remote.client = Session.GameClient.new({}, {
        address = '127.0.0.1',
        port = self.port,
        name = 'Remote',
        world = world,
        input = function()
            return { throttle = remote.throttle, steer = 0 }
        end,
    })
    remote.client:connect()
    self.remote = remote
end

function Tests:measure(host, session)
    local physics = host.world.physics
    local poses = physics:debugPoses()
    local client = session.client
    for netId, car in pairs(client.cars) do
        local view = session.views[netId]
        local body = client.bodies[netId] or (session.server and session.server.bodies[netId])
        if view and body then
            local chassis = chassisOfView(view, car.config.rideHeight)
            local entry = entryFor(poses, body.node.body.raw)
            self:note('speed', math.abs(car.speed or 0) / 100)
            if entry then
                local kind = body.mode == 'follow' and 'followCar' or 'ownCar'
                self:note(kind, distance(chassis, entry))
            end
        end
    end
    -- The stand-ins another client keeps for cars it does not drive, against the pose it draws.
    local remote = self.remote
    if remote and remote.started then
        local remotePoses = remote.world.physics:debugPoses()
        for netId, car in pairs(remote.client.cars) do
            local body = remote.client.bodies[netId]
            if body and body.mode == 'follow' then
                local entry = entryFor(remotePoses, body.node.body.raw)
                if entry then
                    self:note('standIn', distance({ car.x, car.y, car.z }, entry))
                end
            end
        end
    end
    -- The riding walker's capsule against where the car's render pose seats it.
    local walker = session.walker
    if walker then
        local entry = entryFor(poses, walker.body.raw)
        local car, carBody
        local netId = client:getCar()
        if netId then
            car = client.cars[netId]
            carBody = client.bodies[netId] or (session.server and session.server.bodies[netId])
        end
        if entry and car and carBody and carBody.mode == 'dynamic' then
            local m = carBody.node.body:getRenderMatrix()
            local lift = walker.SEAT_LIFT -- the capsule sits this far above its seat
            -- The seat on the drawn car, lifted along the chassis up axis.
            local view = session.views[netId]
            local _, _, seat = client:getCar()
            local at = view.root:pointToWorldSpace(require('source.game.scenes.multiplayerCars.scripts.game.seats').offset(seat))
            local ideal = { at[1] + m[2] * lift, at[2] + m[6] * lift, at[3] + m[10] * lift }
            self:note('seatedCapsule', distance(entry, ideal))
        elseif entry and not walker:isRiding() then
            -- On foot: the drawn model's feet against the capsule's bottom.
            local view = session.walkerViews[client.ownWalkerId]
            if view then
                local m = view.root:getWorldMatrix()
                local feet = { entry[1], entry[2] - walker.settings.standingHeight / 2, entry[3] }
                self:note('footCapsule', distance({ m[4], m[8], m[12] }, feet))
            end
        end
    end
end

function Tests:report()
    local phase = PHASES[self.phase]
    local names = {}
    for name in pairs(self.stats) do
        names[#names + 1] = name
    end
    table.sort(names)
    local parts = {}
    for _, name in ipairs(names) do
        local s = self.stats[name]
        parts[#parts + 1] = ('%s %.3f/%.3f'):format(name, s.sum / s.count, s.max)
    end
    print(('POSES %-13s %s'):format(phase.name, table.concat(parts, '  ')))
    self.stats = {}
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.port = 47960 + math.floor(os.clock() * 100) % 9
        self.session:host('Tester', self.port)
        self.host.world.environment.debug.physics.enabled = true
    end
    local host, session = self.host, self.session
    if not host then
        return
    end
    if self.remote then
        self.remote.world.physics:update(1 / 60)
        self.remote.client:afterPhysics()
        self.remote.client:update(1 / 60)
    end
    if frame == 60 then
        self:startRemote(host)
    elseif frame == 150 then
        local rc = self.remote.client
        rc:sit(rc:findNearbyCar(6))
    end
    if frame < 200 then
        host:update(1 / 60, 1 / 60)
        host:draw()
        return
    end
    if self.remote and not self.remote.started then
        self.remote.started = true
        self.remote.throttle = 1
    end
    local phase = PHASES[self.phase]
    if not phase then
        katsa.event.quit()
        return
    end
    if phase.mode == 'drive' and not self.seated then
        self.seated = true
        session:changeCar()
    end
    if self.seated and frame > 215 then
        host.input.actions.keys.up = true
    end
    local dt = phase.dt or (1 / 200 + self:random() * (1 / 25 - 1 / 200))
    host:update(dt, dt)
    host:draw()
    -- Skip the first frames of a phase while the pose history settles after a dt change.
    self.phaseFrame = self.phaseFrame + 1
    if self.phaseFrame > 10 and (phase.mode == 'foot' or self.seated) then
        self:measure(host, session)
    end
    if self.phaseFrame >= phase.frames then
        self:report()
        self.phase, self.phaseFrame = self.phase + 1, 0
    end
end

return Tests
