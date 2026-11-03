-- Layer groups: the one place that answers "does this camera see this node?".
--
-- Every Node3D carries `layerGroup` (a name from the world's layer matrix). `world:resolveLayerGroup`
-- turns it into the bit `node.layers`; a camera stores the mask of every group it can see. Meshes,
-- decals, billboards, lights, particles, ribbons and picking all test through `Layering.sees`.
local band = require('bit').band

local Layering = {}

function Layering.sees(camera, node)
    return band(node.layers or 1, camera.layers or -1) ~= 0
end

return Layering
