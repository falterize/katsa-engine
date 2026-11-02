local Library = require('./library')
local NativeMath = require('./nativeMath')
local C, cast = Library.C, NativeMath.cast

local ShapeLookup = {}

function ShapeLookup.resolve(raw, sub)
    local body = raw._joltOwner
    if C.JPH_Shape_GetType(raw._joltShape) ~= 1 then
        return body.shapes[1].raw
    end
    local index = C.JPH_CompoundShape_GetSubShapeIndexFromID(
        cast('CompoundShape', raw._joltShape),
        sub,
        body.physics.adapter.subshapeRemainder
    )
    return body.shapes[tonumber(index) + 1] and body.shapes[tonumber(index) + 1].raw
        or body.shapes[1].raw
end

return ShapeLookup
