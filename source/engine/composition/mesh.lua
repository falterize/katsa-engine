-- Composition helper: the material is a real child, never a Mesh3D texture property.
local Mesh = {}

function Mesh.create(world, properties, parent)
    local surface = properties.surfaceAppearance
    properties.surfaceAppearance = nil
    local mesh = world:create('Mesh3D', properties, parent)
    if surface then
        world:create('SurfaceAppearance3D', surface, mesh)
    end
    return mesh
end

return Mesh
