-- Server-side rigid-body car. A Body3D (Dynamic, Jolt) with four raycast wheels: each wheel is a
-- damped spring pushing the chassis up, plus drive, brake and lateral-grip forces at its contact
-- point. Collisions with the terrain, walls and other cars are the physics engine's own.
-- The replicated "model" (position, heading, wheel springs ...) is refreshed from the body.
--
-- Units are meters (the scene uses unitsPerMeter = 1). Heading 0 faces +z.
local O = require('source.engine.physics.3d.valueTypes')
local orientation = require('scene.scripts.game.orientation')

local PhysicsCar = {}
PhysicsCar.__index = PhysicsCar

local TUNING = {
    mass = 1100,
    size = { 1.8, 0.8, 4.2 }, -- chassis box: width, height, length
    mountY = -0.25, -- suspension top, relative to the body center
    wheelRadius = 0.35,
    restLength = 0.4, -- spring length with no load
    droop = 0.15, -- extra ray length so a wheel can hang below its rest position
    gravityScale = 1.8, -- a heavier feel than real gravity: no floating over bumps and ramps
    stiffness = 52000, -- N/m per wheel
    damping = 6500, -- N*s/m per wheel
    gripRate = 14, -- how quickly sideways velocity is removed (1/s)
    gripLimit = 15, -- maximum sideways acceleration (m/s^2)
    yawGain = 12, -- how quickly the body follows the steering yaw rate (1/s)
    maxLateral = 13, -- steering never asks for more sideways acceleration than this (m/s^2)
    levelStiffness = 22, -- anti-roll/pitch assist: pull toward the ground plane (1/s^2) ...
    levelDamping = 8, -- ... and damp the tilt rate (1/s)
    impactSpeed = 3.5, -- sudden velocity change that counts as a collision
}

local function approach(value, target, rate, dt)
    local step = rate * dt
    if value < target then
        return math.min(target, value + step)
    end
    return math.max(target, value - step)
end

-- model: the replicated car (config, wheels, spring ...). world: the scene's World3D.
function PhysicsCar.new(world, model, netId, options)
    options = options or {}
    local t = {}
    for key, value in pairs(TUNING) do
        t[key] = value
    end
    for key, value in pairs(options) do
        t[key] = value
    end
    local config = model.config
    local ground = model.ground(model.x, model.z)
    local height = -t.mountY + t.restLength + t.wheelRadius
    local node = world:create('Body3D', {
        name = 'CarBody' .. netId,
        bodyType = 'Dynamic', -- a custom mass needs a dynamic body; follow mode switches below
        size = { t.size[1], t.size[2], t.size[3] },
        mass = t.mass,
        friction = 0.15,
        restitution = 0.1,
        linearDamping = 0.01,
        angularDamping = 0.8,
        gravityScale = t.gravityScale,
        autoSleep = false,
        position = { model.x, ground + height + 0.1, model.z },
        rotation = { 0, -model.heading, 0 }, -- engine yaw runs opposite to the model heading
    })
    local self = setmetatable({
        model = model,
        node = node,
        tuning = t,
        config = config,
        compression = { 0, 0, 0, 0 },
        grounded = { false, false, false, false },
        velocity = {},
        previous = { 0, 0, 0 },
        angular = O.Vec3.new(),
        rayA = {},
        rayB = {},
        hit = {},
        input = {},
        impacts = {},
        mode = options.mode or 'dynamic',
        angles = {},
        axes = { right = {}, up = {}, forward = {} },
    }, PhysicsCar)
    if self.mode == 'follow' then
        node.bodyType = 'Kinematic'
        node:update(0)
    end
    self.filter = function(other)
        return other ~= node.body and other.canCollide
    end
    return self
end

-- 'dynamic': the car is driven by forces here. 'follow': a kinematic stand-in that copies the
-- replicated model (a car simulated by its driver's client, or another player's car seen from a
-- client that owns one), so the owning simulation still collides with it.
function PhysicsCar:setMode(mode)
    if mode == self.mode then
        return
    end
    self.mode = mode
    if mode == 'dynamic' then
        local model = self.model
        self.node.bodyType = 'Dynamic'
        self.node:update(0)
        local fx, fz = math.sin(math.rad(model.heading)), math.cos(math.rad(model.heading))
        self.node.body:setVelocity({ fx * model.speed, 0, fz * model.speed })
        self.hasPrevious = false
        for i = 1, 4 do
            self.compression[i] = 0
        end
    else
        self.node.bodyType = 'Kinematic'
        self.node:update(0)
    end
end

-- Moves a follow-mode body to the replicated pose.
function PhysicsCar:follow()
    local model = self.model
    local angles = orientation(model.heading, model.pitch or 0, model.roll or 0, self.angles)
    self.node.position = { model.x, model.y, model.z }
    self.node.rotation = { angles[1], angles[2], angles[3] }
    self.node.body:sync()
end

function PhysicsCar:setInput(input)
    self.input = input or {}
end

-- Reads the chassis pose into the axes table and returns the position.
function PhysicsCar:pose()
    local body = self.node.body
    body:sync()
    local m = body._worldPhysicsMatrix
    local a = self.axes
    a.right[1], a.right[2], a.right[3] = m[1], m[5], m[9]
    a.up[1], a.up[2], a.up[3] = m[2], m[6], m[10]
    a.forward[1], a.forward[2], a.forward[3] = m[3], m[7], m[11]
    return m[4], m[8], m[12]
end

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- Applies all car forces for one physics step.
function PhysicsCar:step(dt)
    if self.mode == 'follow' then
        return self:follow()
    end
    local t, model, config = self.tuning, self.model, self.config
    local body = self.node.body
    local px, py, pz = self:pose()
    local a = self.axes
    local up, forward, right = a.up, a.forward, a.right
    local v = body:getVelocity(self.velocity)
    local speed, lateral = dot(v, forward), dot(v, right)
    body.raw:getAngularVelocityTo(self.angular)
    local yawRate = self.angular.x * up[1] + self.angular.y * up[2] + self.angular.z * up[3]

    local input = self.input
    local throttle = math.max(-1, math.min(1, input.throttle or 0))
    local boosting = input.nitro == true and model.nitro > 0 and throttle > 0
    if boosting then
        model.nitro = math.max(0, model.nitro - config.nitroDrain * dt)
    end
    local top = config.maxSpeed * (boosting and config.nitroSpeedMultiplier or 1)
    local limit = config.maxSteer / (1 + math.abs(speed) / config.steerSpeedFalloff)
    model.steerAngle =
        approach(model.steerAngle, math.max(-1, math.min(1, input.steer or 0)) * limit, 180, dt)

    -- Suspension: ray down from each mount, spring + damper along the chassis up axis.
    local grounded = 0
    local nx, ny, nz = 0, 0, 0 -- summed ground normals under the wheels
    local rayLength = t.restLength + t.wheelRadius + t.droop
    local mass = t.mass
    for i, wheel in ipairs(model.wheels) do
        local ox = right[1] * wheel[1] + up[1] * t.mountY + forward[1] * wheel[2]
        local oy = right[2] * wheel[1] + up[2] * t.mountY + forward[2] * wheel[2]
        local oz = right[3] * wheel[1] + up[3] * t.mountY + forward[3] * wheel[2]
        local mx, my, mz = px + ox, py + oy, pz + oz
        local ra, rb = self.rayA, self.rayB
        ra[1], ra[2], ra[3] = mx, my, mz
        rb[1], rb[2], rb[3] = mx - up[1] * rayLength, my - up[2] * rayLength, mz - up[3] * rayLength
        local hit = body.physics:raycast(ra, rb, self.filter, self.hit)
        local length = t.restLength + t.droop
        self.grounded[i] = false
        if hit then
            local distance = hit.fraction * rayLength
            nx, ny, nz = nx + hit.normal[1], ny + hit.normal[2], nz + hit.normal[3]
            length = math.max(0, distance - t.wheelRadius)
            local x = t.restLength - length
            local rate = (x - self.compression[i]) / dt
            self.compression[i] = x
            if x > 0 then
                local force = math.min(t.stiffness * x + t.damping * rate, mass * 9.81 * t.gravityScale * 1.5)
                if force > 0 then
                    body:applyForceAt({ up[1] * force, up[2] * force, up[3] * force }, { mx, my, mz })
                end
                self.grounded[i] = true
                grounded = grounded + 1
            end
        else
            self.compression[i] = 0
        end
        -- Wheel height in the view's car space: the view places wheels at 0.4 + spring.
        model.spring[i] = (config.rideHeight + t.mountY - length) - 0.4
    end

    local share = grounded / 4
    if grounded > 0 then
        -- Drive / brake along the chassis forward axis, applied at the center.
        local longitudinal = 0
        if throttle > 0 then
            if speed < -0.5 then
                longitudinal = config.brake * throttle
            else
                local taper = math.max(0, 1 - (speed / top) ^ 2)
                longitudinal = config.acceleration * (boosting and config.nitroMultiplier or 1) * throttle * taper
            end
        elseif throttle < 0 then
            if speed > 0.5 then
                longitudinal = config.brake * throttle
            else
                local taper = math.max(0, 1 - (-speed) / config.reverseSpeed)
                longitudinal = config.acceleration * 0.6 * throttle * taper
            end
        else
            longitudinal = -math.max(-config.rolling, math.min(config.rolling, speed * 4))
        end
        longitudinal = longitudinal - speed * config.drag
        local f = longitudinal * mass * share
        body:applyForce({ forward[1] * f, forward[2] * f, forward[3] * f })

        -- Lateral grip removes sideways slip, limited by what the tires can hold.
        local wanted = -lateral * t.gripRate
        local accel = math.max(-t.gripLimit, math.min(t.gripLimit, wanted)) * mass * share
        body:applyForce({ right[1] * accel, right[2] * accel, right[3] * accel })

        -- Steering: follow the bicycle-model yaw rate for the current speed and wheel angle.
        local target = speed / config.wheelBase * math.tan(math.rad(model.steerAngle))
        -- A turn tighter than the tires hold only throws the car sideways onto its roof.
        local cap = t.maxLateral / math.max(2, math.abs(speed))
        target = math.max(-cap, math.min(cap, target))
        local inertia = mass * (t.size[3] ^ 2 + t.size[1] ^ 2) / 12
        local torque = (target - yawRate) * t.yawGain * inertia * share
        body:applyTorque({ up[1] * torque, up[2] * torque, up[3] * torque })

        -- Anti-roll assist: a stabiliser that levels the chassis with the ground under the wheels
        -- and damps roll and pitch, so hard cornering and bumps cannot tip the car over.
        local length = math.sqrt(nx * nx + ny * ny + nz * nz)
        if length > 1e-4 then
            nx, ny, nz = nx / length, ny / length, nz / length
            -- up x normal: the axis that turns the chassis up toward the ground normal.
            local ex = up[2] * nz - up[3] * ny
            local ey = up[3] * nx - up[1] * nz
            local ez = up[1] * ny - up[2] * nx
            local wx, wy, wz = self.angular.x, self.angular.y, self.angular.z
            local spin = wx * up[1] + wy * up[2] + wz * up[3]
            -- Tilt rate without the yaw spin.
            wx, wy, wz = wx - up[1] * spin, wy - up[2] * spin, wz - up[3] * spin
            local sx, sy, sz = t.levelStiffness * ex - t.levelDamping * wx,
                t.levelStiffness * ey - t.levelDamping * wy,
                t.levelStiffness * ez - t.levelDamping * wz
            -- Roll inertia of the box (about forward), used for both axes: gentle on pitch.
            local rollInertia = mass * (t.size[1] ^ 2 + t.size[2] ^ 2) / 12 * 2.5
            local k = rollInertia * share
            body:applyTorque({ sx * k, sy * k, sz * k })
        end
    end
    self.boosting = boosting
    self.lastSpeed = speed
end

-- Refreshes the replicated model from the body and queues collision impacts.
function PhysicsCar:readState()
    if self.mode == 'follow' then
        return
    end
    local model = self.model
    local px, py, pz = self:pose()
    local a = self.axes
    local forward, right, up = a.forward, a.right, a.up
    local v = self.node.body:getVelocity(self.velocity)
    model.x, model.y, model.z = px, py, pz
    model.heading = (math.deg(math.atan2(forward[1], forward[3]))) % 360
    -- Pitch (nose up positive) and roll (right side up positive) in the car's own frame.
    local pitch = math.asin(math.max(-1, math.min(1, forward[2])))
    model.pitch = math.deg(pitch)
    model.roll = math.deg(math.asin(math.max(-1, math.min(1, right[2] / math.max(0.2, math.cos(pitch))))))
    model.speed = dot(v, forward)
    model.slide = dot(v, right)
    model.vertical = v[2]
    -- A collision shows up as a sudden velocity change that gravity and the springs cannot make.
    local prev = self.previous
    local dvx, dvy, dvz = v[1] - prev[1], v[2] - prev[2], v[3] - prev[3]
    if self.hasPrevious and next(self.node.body:getContacts()) then
        local dh = math.sqrt(dvx * dvx + dvz * dvz)
        if dh > self.tuning.impactSpeed then
            -- The push direction (into the body) in car space, with the contact on the opposite side.
            local nx, nz = dvx / dh, dvz / dh
            local lx, lz = dot({ nx, 0, nz }, right), dot({ nx, 0, nz }, forward)
            local length = math.sqrt(lx * lx + lz * lz)
            if length > 1e-4 then
                lx, lz = lx / length, lz / length
                local size = self.tuning.size
                self.impacts[#self.impacts + 1] = {
                    x = -lx * size[1] * 0.5,
                    z = -lz * size[3] * 0.5,
                    nx = lx,
                    nz = lz,
                    speed = dh,
                }
            end
        end
    end
    prev[1], prev[2], prev[3] = v[1], v[2], v[3]
    self.hasPrevious = true
end

-- True once the car has been upside down or far below the arena for a while.
function PhysicsCar:needsReset(dt)
    if self.mode == 'follow' then
        return false
    end
    local flipped = self.axes.up[2] < 0.25 and math.abs(self.model.speed) < 3
    self.flippedFor = flipped and (self.flippedFor or 0) + dt or 0
    return self.flippedFor > 3 or self.model.y < -30
end

function PhysicsCar:respawn(x, z, heading)
    local body = self.node.body
    local ground = self.model.ground(x, z)
    -- Moving the node is how a Body3D is repositioned; sync() carries the pose to the body.
    self.node.position = { x, ground + 1.2, z }
    self.node.rotation = { 0, -heading, 0 }
    body:sync()
    body:setVelocity({ 0, 0, 0 })
    body.raw:setAngularVelocity(O.Vec3.new(0, 0, 0))
    self.flippedFor = 0
    self.hasPrevious = false
end

function PhysicsCar:destroy()
    self.node:destroy()
end

return PhysicsCar
