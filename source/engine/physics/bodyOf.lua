-- Returns the physics object attached to a node, or nil.
-- World nodes also keep their physics *service* in `physics`, so the field alone is not enough:
-- only a Body owns a `node` pointing back at the node that carries it.
local rawget = rawget

local function bodyOf(node)
    local physics = node and rawget(node, 'physics')
    if physics and physics.node == node then
        return physics
    end
end

return bodyOf
