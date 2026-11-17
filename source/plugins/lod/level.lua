local ipairs = require('source.engine.math.array').ipairs

-- What a LODGroup does to the meshes of one level besides showing or hiding it: fading (the
-- transparency of every Mesh3D inside the level) and shadows. The authored values are remembered on
-- the mesh the first time, so they are restored when the effect ends.
local LodLevel = {}

-- The Mesh3D nodes of a level (the node itself and everything below it); a new table.
function LodLevel.meshes(node)
    local list = {}
    if node:isA('Mesh3D') then
        list[1] = node
    end
    for _, child in ipairs(node:getDescendants()) do
        if child:isA('Mesh3D') then
            list[#list + 1] = child
        end
    end
    return list
end

-- Draws the meshes `alpha` opaque (1 = as authored, 0 = invisible).
function LodLevel.setAlpha(meshes, alpha)
    for _, mesh in ipairs(meshes) do
        mesh._lodTransparency = mesh._lodTransparency or mesh.transparency or 0
        mesh.transparency = 1 - (1 - mesh._lodTransparency) * alpha
    end
end

function LodLevel.restoreAlpha(meshes)
    for _, mesh in ipairs(meshes) do
        if mesh._lodTransparency then
            mesh.transparency, mesh._lodTransparency = mesh._lodTransparency, nil
        end
    end
end

-- Lets the meshes cast shadows only when `allowed` and when they were authored to.
function LodLevel.setShadows(meshes, allowed)
    for _, mesh in ipairs(meshes) do
        if mesh._lodCastShadow == nil then
            mesh._lodCastShadow = mesh.castShadow
        end
        mesh.castShadow = mesh._lodCastShadow and allowed
    end
end

return LodLevel
