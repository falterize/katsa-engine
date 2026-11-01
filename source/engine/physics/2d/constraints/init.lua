-- Solver joint builders per Constraint2D kind. Spring shares the distance builder.
local Builders = {}
local modules = {
    Hinge = 'hinge',
    Prismatic = 'prismatic',
    Weld = 'weld',
    Rope = 'rope',
    Distance = 'distance',
    Spring = 'distance',
    Wheel = 'wheel',
    Friction = 'friction',
    Motor = 'motor',
    Pulley = 'pulley',
    Gear = 'gear',
    Mouse = 'mouse',
}

function Builders.build(self, context)
    local module = modules[self.kind]
    if not module then
        error('Unsupported Constraint2D kind: ' .. tostring(self.kind))
    end
    return require('source.engine.physics.2d.constraints.' .. module)(self, context)
end

return Builders
