-- katsa.physics: 2D physics over Box2D 2.3.1 (katsa_box2d). Lengths are given in pixels
-- and
-- divided by the meter scale; forces scale with the meter, torques and inertia with its square.
local Scale = require('source.katsa.physics.scale')

local Physics = {
    setMeter = Scale.setMeter,
    getMeter = Scale.getMeter,
}

-- Each module exposes its public constructors as `new*` (and `getDistance`).
for _, name in ipairs({ 'shape', 'fixture', 'body', 'world', 'joint' }) do
    for key, value in pairs(require('source.katsa.physics.' .. name)) do
        if key:find('^new') or key == 'getDistance' then
            Physics[key] = value
        end
    end
end

return Physics
