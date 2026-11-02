-- Car node. The folder is one node split into modules:
--   model.lua       deterministic driving, suspension, nitro, seats
--   collision.lua   obstacle and car-versus-car response
--   deformation.lua replicable body dents
-- Other scene code can load a part with require('./model').
local Model = require('./model')
local Collision = require('./collision')
local Deformation = require('./deformation')

local Car = {
    base = 'Mesh3D',
    properties = {
        nitro = { hint = 'Nitro tank, 0 to 1.', min = 0, max = 1 },
    },
    Model = Model,
    Collision = Collision,
    Deformation = Deformation,
}

function Car.initialize(self)
    self.car = Model.new(self.carConfig, self.ground)
    self.dents = Deformation.new()
    self.color = self.color or { 0.9, 0.25, 0.2, 1 }
end

-- Copies the simulated pose onto the visual node: position, yaw and spring tilt.
function Car:applyPose()
    local car = self.car
    local pitch, roll = car:tilt()
    self.position = { car.x, car.y, car.z }
    self.rotation = { pitch, car.heading, roll }
end

function Car:update()
    if self.car then
        self:applyPose()
    end
end

function Car.register(world)
    return world:registerNodeType('Car', Car)
end

return Car
