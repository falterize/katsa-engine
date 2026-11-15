local ipairs = require('source.engine.math.array').ipairs

-- Example-only shared directional setup; every source is a real hierarchy node.
local Directional = {}

function Directional.create(world, name)
    name = name or 'Sun'
    for _, node in ipairs(world.directionalLights) do
        if node.name == name and not node.destroyed then
            return node
        end
    end
    return world:create('DirectionalLight3D', {
        name = name,
        rotation = { 63.434948822922, 53.130102354156, 0 },
        color = { 255, 238, 210 },
        brightness = 1,
    })
end

return Directional
