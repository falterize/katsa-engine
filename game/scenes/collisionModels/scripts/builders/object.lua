local Object = {}

function Object.create(scene, name, position, size, properties, bodySettings)
    properties = properties or {}
    properties.name = name
    properties.position = position
    properties.size = size
    local mesh = require('source.engine.composition.mesh').create(scene.world, properties)
    if bodySettings then
        scene.physics:addBody(mesh, bodySettings)
    end
    return mesh
end

return Object
