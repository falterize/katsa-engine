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

function CarView.new(scene, netId, model)
    local world = scene.world
    local color = model.isBot and { 0.12, 0.12, 0.14 } or PALETTE[(netId - 1) % #PALETTE + 1]
    local geometry, rest = Body.create()
    local self = setmetatable({
        model = model,
        netId = netId,
        geometry = geometry,
        rest = rest,
        dentCount = -1,
        wheels = {},
        spin = 0,
        angles = {},
    }, CarView)
    self.root = world:create('Node3D', { name = 'Car' .. netId })
    self.body = world:create('Mesh3D', {
        name = 'Body' .. netId,
        geometry = geometry,
        color = color,
    }, self.root)
    for index, offset in ipairs(model.wheels) do
        self.wheels[index] = world:create('Mesh3D', {
            name = 'Wheel' .. netId .. '_' .. index,
            kind = 'sphere',
            size = { 0.35, 0.8, 0.8 },
            color = { 0.08, 0.08, 0.08 },
            position = { offset[1], 0.4, offset[2] },
        }, self.root)
    end
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
    Body.deform(self.geometry, self.rest, self.model.dents)
    self.dentCount = #self.model.dents.dents
end

-- Moves the nodes to the model state. Call every frame.
function CarView:update(dt)
    local car = self.model
    self.root.position = { car.x, car.y - car.config.rideHeight, car.z }
    self.root.rotation = orientation(car.heading, car.pitch or 0, car.roll or 0, self.angles)
    self.spin = (self.spin + car.speed * dt / 0.4 * 57.3) % 360
    for index, wheel in ipairs(self.wheels) do
        local steer = index <= 2 and car.steerAngle or 0
        wheel.rotation = { self.spin, steer, 0 }
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

function CarView:markDirty()
    self.dirty = true
end

function CarView:destroy()
    self.root:destroy()
end

return CarView
