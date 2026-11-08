local Models = require('source.engine.import.models')

-- Shows assets/models/Destare.blend (a .blend imported directly) a few steps from the spawn point.
-- .blend files are converted by the installed Blender (KATSA_BLENDER or the usual install folders)
-- or by a packaged `Destare.blend.glb`; without either the prop is skipped and the game still runs.
local Builder = {}

Builder.PATH = 'scene://models/Destare.blend'

function Builder.create(scene)
    local ok, result = pcall(function()
        local model = Models.load(Builder.PATH, scene.resources)
        return Models.instantiate(scene.world, model, {
            name = 'Destare',
            position = { 3, 0, -3 },
            rotation = { 0, 180, 0 },
        })
    end)
    if not ok then
        katsa.log.warn('Destare.blend was not loaded: ' .. tostring(result):match('[^\n]+'))
        return nil
    end
    return result
end

return Builder
