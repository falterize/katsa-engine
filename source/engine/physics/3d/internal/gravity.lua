local O = require('source.engine.physics.3d.valueTypes')
local WorldGravity = require('source.engine.world.gravity')
local Gravity = {}

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

function Gravity.install(Physics)
    function Physics:setGravity(x, y, z)
        if type(x) ~= 'number' then
            x, y, z = x[1], x[2], x[3]
        end
        assert(finite(x) and finite(y) and finite(z), 'Gravity vector must be finite')
        self.gravity[1], self.gravity[2], self.gravity[3] = x, y, z
        self.world:setGravity(O.Vec3.new(x / self.units, y / self.units, z / self.units))
        for _, body in ipairs(self.bodies) do
            if body.type == 'Dynamic' then
                body.raw:wakeUp()
            end
        end
        WorldGravity.read(self, x, y, z)
    end

    function Physics:getGravity()
        return self.gravity[1], self.gravity[2], self.gravity[3]
    end
end

return Gravity
