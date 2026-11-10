-- Render cutoff distance (`maxDistance`) shared by Mesh3D, Decal3D, particles and ribbons.
-- 0 means unlimited. A node is kept while its bounding sphere still reaches into the range.
local V = require('../core.validate')

local RenderRange = {}

function RenderRange.normalize(node, default)
    if node.maxDistance == nil then
        node.maxDistance = default or 0
    end
    V.number(node.maxDistance, 'maxDistance', 0)
end

-- `distanceSquared` is the squared camera distance of the sphere centre, `radius` its radius.
function RenderRange.within(limit, distanceSquared, radius)
    return not limit or limit <= 0 or distanceSquared <= (limit + (radius or 0)) ^ 2
end

function RenderRange.describe(class)
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    schema.maxDistance = schema.maxDistance or {}
    schema.maxDistance.min = 0
end

return RenderRange
