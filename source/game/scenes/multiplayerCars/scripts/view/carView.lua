-- The visible side of one car: a dent-able body and four wheels, driven by the model state.
local Body = require('scene.scripts.view.carMesh')

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
    self:refreshDents()
    return self
end

function CarView:refreshDents()
    Body.deform(self.geometry, self.rest, self.model.dents)
    self.dentCount = #self.model.dents.dents
end

-- Moves the nodes to the model state. Call every frame.
function CarView:update(dt)
    local car = self.model
    self.root.position = { car.x, car.y - car.config.rideHeight, car.z }
    local pitch, roll = car:tilt()
    self.root.rotation = { -pitch, car.heading, -roll }
    self.spin = (self.spin + car.speed * dt / 0.4 * 57.3) % 360
    for index, wheel in ipairs(self.wheels) do
        local steer = index <= 2 and car.steerAngle or 0
        wheel.rotation = { self.spin, steer, 0 }
        local offset = car.wheels[index]
        wheel.position = { offset[1], 0.4 + car.spring[index], offset[2] }
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
