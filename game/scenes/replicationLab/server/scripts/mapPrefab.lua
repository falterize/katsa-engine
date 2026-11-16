-- The `main.lua` of a map prefab scene: boxes marked with the `Solid` attribute (each client gives
-- them physics, see scripts/game/solids.lua) around the origin of the prefab.
local Packed = require('source.engine.scenes.packed.scene')

local MapPrefab = {}

function MapPrefab.define(spec)
    return Packed.define(function(scene)
        for index, box in ipairs(spec.boxes) do
            scene.world
                :create('Mesh3D', {
                    name = 'Part' .. index,
                    position = { box[1], box[2], box[3] },
                    size = { box[4], box[5], box[6] },
                    color = box[7],
                })
                :setAttribute('Solid', true)
        end
        return spec
    end)
end

return MapPrefab
