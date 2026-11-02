-- The visible side of one car: a dent-able body and four wheels, driven by the model state.
local Body = require('scene.scripts.view.carMesh')

local orientation = require('scene.scripts.game.orientation')

local CarView = {}
CarView.__index = CarView

local PALETTE = {
    { 0.85, 0.2, 0.18 },
    { 0.2, 0.45, 0.85 },
    { 0.9, 0.75, 0.2 },
    { 0.3, 0.75, 0.4 },
    { 0.7, 0.35, 0.8 },
    { 0.9, 0.5, 0.2 },
}

local WHEEL_RADIUS, WHEEL_WIDTH = 0.35, 0.28

-- A wheel: a tire and a five-spoke rim as children of one node, so the whole wheel spins/steers.
local function buildWheel(world, parent, name, position)
    local node = world:create('Node3D', { name = name, position = position }, parent)
    local tire, rim = Body.wheelGeometry(WHEEL_RADIUS, WHEEL_WIDTH)
    world:create('Mesh3D', { name = name .. 'Tire', geometry = tire, color = { 0.06, 0.06, 0.07 } }, node)
    world:create('Mesh3D', { name = name .. 'Rim', geometry = rim, color = { 0.78, 0.8, 0.84 } }, node)
    return node
end

local function light(world, parent, name, x, y, z, color)
    return world:create('Mesh3D', {
        name = name,
        kind = 'cube',
        position = { x, y, z },
        size = { 0.3, 0.14, 0.06 },
        color = color,
        unlit = true,
        castShadow = false,
    }, parent)
end

function CarView.new(scene, netId, model)
    local world = scene.world
    local color = model.isBot and { 0.12, 0.12, 0.14 } or PALETTE[(netId - 1) % #PALETTE + 1]
    local paint, glass = Body.create()
    local self = setmetatable({
        model = model,
        netId = netId,
        scene = scene,
        paint = paint,
        glass = glass,
        dentCount = -1,
        wheels = {},
        debris = {},
        spin = 0,
        angles = {},
    }, CarView)
    self.root = world:create('Node3D', { name = 'Car' .. netId })
    self.body = world:create('Mesh3D', {
        name = 'Body' .. netId,
        geometry = paint.geometry,
        color = color,
    }, self.root)
    self.window = world:create('Mesh3D', {
        name = 'Glass' .. netId,
        geometry = glass.geometry,
        color = { 0.08, 0.12, 0.16 },
    }, self.root)
    for index, offset in ipairs(model.wheels) do
        self.wheels[index] =
            buildWheel(world, self.root, 'Wheel' .. netId .. '_' .. index, { offset[1], 0.4, offset[2] })
    end
    light(world, self.root, 'HeadL' .. netId, -0.58, 0.62, 2.1, { 1, 0.96, 0.8 })
    light(world, self.root, 'HeadR' .. netId, 0.58, 0.62, 2.1, { 1, 0.96, 0.8 })
    light(world, self.root, 'TailL' .. netId, -0.6, 0.78, -2.12, { 0.9, 0.05, 0.05 })
    light(world, self.root, 'TailR' .. netId, 0.6, 0.78, -2.12, { 0.9, 0.05, 0.05 })
    self:buildNitro(world, model)
    self:refreshDents()
    return self
end

local function ramp(a, b, c)
    return { { time = 0, value = a }, { time = 0.5, value = b }, { time = 1, value = c } }
end

-- Two exhaust flames, lit only while the nitro tank is draining.
function CarView:buildNitro(world, model)
    self.flames = {}
    local rearZ = (model.wheels[3] and model.wheels[3][2] or -1.3) - 1.5
    for side = 1, 2 do
        local ok, emitter = pcall(function()
            return world:create('ParticleEmitter3D', {
                name = 'Nitro' .. self.netId .. '_' .. side,
                position = { side == 1 and -0.45 or 0.45, 0.45, rearZ },
                rate = 0,
                lifetime = { 0.25, 0.5 },
                speed = { 5, 9 },
                startSize = { 0.5, 0.9 },
                spread = 8,
                blendMode = 'Add',
                drag = 0.5,
                lifetimeBindings = {
                    size = ramp(1, 0.7, 0.1),
                    color = ramp({ 0.5, 0.8, 1 }, { 0.15, 0.4, 1 }, { 0.05, 0.05, 0.4 }),
                },
            }, self.root)
        end)
        if ok then
            self.flames[#self.flames + 1] = emitter
        end
    end
end

function CarView:refreshDents()
    Body.deform(self.paint.geometry, self.paint.rest, self.model.dents)
    Body.deform(self.glass.geometry, self.glass.rest, self.model.dents)
    self.dentCount = #self.model.dents.dents
end

-- A wheel was torn off: hide it and let a copy roll away as a loose rigid body (cosmetic, local).
function CarView:shedWheel(index)
    local wheel, car = self.wheels[index], self.model
    if not wheel or not self.scene.world.physics then
        return
    end
    wheel.visible = false
    local offset = car.wheels[index]
    local heading = math.rad(car.heading)
    local fx, fz = math.sin(heading), math.cos(heading)
    local rx, rz = fz, -fx
    local x = car.x + rx * offset[1] + fx * offset[2]
    local z = car.z + rz * offset[1] + fz * offset[2]
    local y = car.y - car.config.rideHeight + 0.45
    local world = self.scene.world
    local debris = world:create('Body3D', {
        name = 'LostWheel' .. self.netId .. '_' .. index,
        bodyType = 'Dynamic',
        position = { x, y, z },
        size = { WHEEL_RADIUS * 2, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2 },
        collider = { shape = 'Sphere', radius = WHEEL_RADIUS },
        mass = 22,
        friction = 0.8,
        restitution = 0.35,
        angularDamping = 0.2,
    })
    local tire, rim = Body.wheelGeometry(WHEEL_RADIUS, WHEEL_WIDTH)
    world:create('Mesh3D', { name = 'LostTire' .. self.netId .. '_' .. index, geometry = tire, color = { 0.06, 0.06, 0.07 } }, debris)
    world:create('Mesh3D', { name = 'LostRim' .. self.netId .. '_' .. index, geometry = rim, color = { 0.78, 0.8, 0.84 } }, debris)
    local side = offset[1] < 0 and -1 or 1
    debris.body:setVelocity({
        fx * (car.speed or 0) + rx * (car.slide or 0) + rx * side * 4,
        3.5,
        fz * (car.speed or 0) + rz * (car.slide or 0) + rz * side * 4,
    })
    self.debris[#self.debris + 1] = { node = debris, age = 0 }
end

-- Moves the nodes to the model state. Call every frame.
function CarView:update(dt)
    self:ageDebris(dt)
    local car = self.model
    self.root.position = {
        car.rx or car.x,
        (car.ry or car.y) - car.config.rideHeight,
        car.rz or car.z,
    }
    self.root.rotation = orientation(
        car.rheading or car.heading,
        car.rpitch or car.pitch or 0,
        car.rroll or car.roll or 0,
        self.angles
    )
    self.spin = (self.spin + car.speed * dt / 0.35 * 57.3) % 360
    for index, wheel in ipairs(self.wheels) do
        local steer = index <= 2 and car.steerAngle or 0
        -- The car root turns by -heading (engine yaw opposes the model heading), so a wheel
        -- steering toward positive heading needs the same sign flip.
        wheel.rotation = { -self.spin, -steer, 0 }
        wheel.visible = math.floor((car.detached or 0) / 2 ^ (index - 1)) % 2 == 0
        local offset = car.wheels[index]
        wheel.position = { offset[1], 0.4 + car.spring[index], offset[2] }
    end
    local burning = self.lastNitro ~= nil and car.nitro < self.lastNitro - 1e-4 and car.speed > 1
    self.lastNitro = car.nitro
    for _, flame in ipairs(self.flames or {}) do
        flame.rate = burning and 70 or 0
    end
    if self.dentCount ~= #car.dents.dents or self.dirty then
        self:refreshDents()
        self.dirty = false
    end
end

function CarView:ageDebris(dt)
    for index = #self.debris, 1, -1 do
        local item = self.debris[index]
        item.age = item.age + dt
        if item.age > 25 then
            item.node:destroy()
            table.remove(self.debris, index)
        end
    end
end

function CarView:markDirty()
    self.dirty = true
end

function CarView:destroy()
    for _, item in ipairs(self.debris) do
        item.node:destroy()
    end
    self.debris = {}
    self.root:destroy()
end

return CarView
