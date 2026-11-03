-- Render cutoff distance (`maxDistance`) shared by Mesh3D, Decal3D, particles and ribbons.
-- 0 means unlimited. A node is kept while its bounding sphere still reaches into the range.
local V = require('../core.validate')

local RenderRange = {}

local hint = 'Render cutoff distance from the camera in world units; 0 disables it.'

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

function RenderRange.describe(class, text)
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    schema.maxDistance = schema.maxDistance or {}
    schema.maxDistance.min = 0
    schema.maxDistance.hint = schema.maxDistance.hint or text or hint
end

return RenderRange
